const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const parseInt = std.fmt.parseInt;

const SECONDS_IN_A_DAY: u64 = 60 * 60 * 24;
const DAYS_IN_YEAR: u64 = 365;
const DAYS_IN_400_YEARS: u64 = 146097;
const DAYS_FROM_1970_TO_0000: u64 = 719468;

const Timeframe = union(enum) {
    years: u16,
    months: u32,
    days: u32,
    hours: u32,
    minutes: u32,
    seconds: u32,
};

const RangeOptions = struct {
    step: Timeframe,
    start_date: Datetime,
    end_date: Datetime,
};

const Eq = enum {
    EQ,
    LT,
    GT,
};

const Datetime = struct {
    years: u16 = 1970,
    months: u8 = 1,
    days: u8 = 1,
    hours: u8 = 0,
    minutes: u8 = 0,
    seconds: u8 = 0,

    pub fn now() Datetime {
        return Datetime.from_timestamp(std.time.timestamp());
    }

    pub fn from_timestamp(stamp: i64) Datetime {
        // Calculate the number of days since the epoch and adjust by the offset
        const shifted: i64 = @divFloor(stamp, SECONDS_IN_A_DAY) + DAYS_FROM_1970_TO_0000;

        // Determine the 400-year era and day of the era
        const era: i64 = @divTrunc((if (shifted >= 0) shifted else shifted - DAYS_IN_400_YEARS), DAYS_IN_400_YEARS);
        const doe: u64 = @intCast(shifted - era * DAYS_IN_400_YEARS);

        // Calculate the year of the era
        const yoe: u64 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / DAYS_IN_YEAR;
        var years: i64 = @as(i64, @intCast(yoe)) + era * 400;

        // Calculate the day of the year and month part
        const doy: u64 = doe - (DAYS_IN_YEAR * yoe + yoe / 4 - yoe / 100);
        const mp: u64 = (5 * doy + 2) / 153;
        const days: u64 = doy - (153 * mp + 2) / 5 + 1;
        const months: u64 = if (mp < 10) mp + 3 else mp - 9;

        // Adjust the year if the month is January or February
        if (months <= 2) years += 1;

        // Calculate hours, minutes, and seconds
        const seconds: isize = @mod(stamp, 60);
        const total_minutes: isize = @divTrunc(stamp, 60);
        const minutes: isize = @mod(total_minutes, 60);
        const total_hours: isize = @divTrunc(total_minutes, 60);
        const hours: isize = @mod(total_hours, 24);

        // Cast years to u64 and truncate to u16 for the struct
        const years_casted: u64 = @intCast(years);

        return Datetime{
            .years = @truncate(years_casted),
            .months = @truncate(months),
            .days = @truncate(days),
            .hours = @truncate(@as(usize, @intCast(hours))),
            .minutes = @truncate(@as(usize, @intCast(minutes))),
            .seconds = @truncate(@as(usize, @intCast(seconds))),
        };
    }

    pub fn to_timestamp(self: Datetime) i64 {
        const years = @as(i64, @intCast(self.years));
        const months = @as(u64, @intCast(self.months));
        const days = @as(u64, @intCast(self.days));
        const hours = @as(i64, @intCast(self.hours));
        const minutes = @as(i64, @intCast(self.minutes));
        const seconds = @as(i64, @intCast(self.seconds));

        const y: i64 = if (months <= 2) years - 1 else years;
        const era: i64 = @divTrunc((if (y >= 0) y else y - 399), 400);
        const yoe: u64 = @intCast(y - era * 400);
        const doy: u64 = ((153 * if (months > 2) months - 3 else months + 9) + 2) / 5 + days - 1;
        const doe: u64 = yoe * 365 + yoe / 4 - yoe / 100 + doy;

        const days_to_seconds: i64 = 60 * 60 * 24 * (era * 146097 + @as(i64, @intCast(doe)) - 719468);
        const hours_to_seconds: i64 = hours * 60 * 60;
        const minutes_to_seconds: i64 = minutes * 60;

        return days_to_seconds + hours_to_seconds + minutes_to_seconds + seconds;
    }

    pub fn format(self: Datetime, _: anytype, _: anytype, writer: anytype) !void {
        const formatting = "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z";
        const args = .{ self.years, self.months, self.days, self.hours, self.minutes, self.seconds };

        try writer.print(formatting, args);
    }

    pub fn parse(input: []const u8) !Datetime {
        var fixed_reader = std.io.fixedBufferStream(input);
        var reader = fixed_reader.reader();

        var year_buf: [4]u8 = undefined;
        var month_buf: [2]u8 = undefined;
        var day_buf: [2]u8 = undefined;
        var hours_buf: [2]u8 = undefined;
        var mins_buf: [2]u8 = undefined;
        var sec_buf: [2]u8 = undefined;

        _ = try reader.readAtLeast(&year_buf, 4);
        try reader.skipBytes(1, .{});
        _ = try reader.readAtLeast(&month_buf, 2);
        try reader.skipBytes(1, .{});
        _ = try reader.readAtLeast(&day_buf, 2);
        try reader.skipBytes(1, .{});
        _ = try reader.readAtLeast(&hours_buf, 2);
        try reader.skipBytes(1, .{});
        _ = try reader.readAtLeast(&mins_buf, 2);
        try reader.skipBytes(1, .{});
        _ = try reader.readAtLeast(&sec_buf, 2);

        return Datetime{
            .years = try parseInt(u16, &year_buf, 10),
            .months = try parseInt(u8, &month_buf, 10),
            .days = try parseInt(u8, &day_buf, 10),
            .hours = try parseInt(u8, &hours_buf, 10),
            .minutes = try parseInt(u8, &mins_buf, 10),
            .seconds = try parseInt(u8, &sec_buf, 10),
        };
    }

    pub fn add_seconds(self: Datetime, seconds: u32) Datetime {
        var stamp = self.to_timestamp();

        stamp += @as(i32, @intCast(seconds));

        return Datetime.from_timestamp(stamp);
    }

    pub fn add_minutes(self: Datetime, minutes: u32) Datetime {
        return self.add_seconds(minutes * 60);
    }

    pub fn add_hours(self: Datetime, hours: u32) Datetime {
        return self.add_minutes(hours * 60);
    }

    pub fn add_days(self: Datetime, days: u32) Datetime {
        return self.add_hours(days * 24);
    }

    pub fn add_months(self: Datetime, months: u32) Datetime {
        if (months == 0) return self;

        var days: u32 = 0;
        var months_to_add = months;
        var current_year = self.years;
        var current_month = self.months;

        while (months_to_add > 0) {
            days += days_in_month(current_year, current_month);

            if (current_month + 1 == 13) {
                current_month = 1;
                current_year += 1;
            } else {
                current_month += 1;
            }

            months_to_add -= 1;
        }

        return self.add_days(days);
    }

    pub fn add_years(self: Datetime, years: u16) Datetime {
        if (years == 0) return self;

        var days: u32 = 0;
        var years_to_add = years;
        var current_year = self.years;

        while (years_to_add > 0) {
            days += days_in_year(current_year);
            current_year += 1;
            years_to_add -= 1;
        }

        return self.add_days(days);
    }

    pub fn add(self: Datetime, time_frame: Timeframe) Datetime {
        return switch (time_frame) {
            .years => |years| self.add_years(years),
            .months => |months| self.add_months(months),
            .days => |days| self.add_days(days),
            .hours => |hours| self.add_hours(hours),
            .minutes => |minutes| self.add_minutes(minutes),
            .seconds => |seconds| self.add_seconds(seconds),
        };
    }
    pub fn subtract_seconds(self: Datetime, seconds: u32) Datetime {
        var stamp = self.to_timestamp();

        stamp -= @as(i32, @intCast(seconds));

        return Datetime.from_timestamp(stamp);
    }

    pub fn subtract_minutes(self: Datetime, minutes: u32) Datetime {
        return self.subtract_seconds(minutes * 60);
    }

    pub fn subtract_hours(self: Datetime, hours: u32) Datetime {
        return self.subtract_minutes(hours * 60);
    }

    pub fn subtract_days(self: Datetime, days: u32) Datetime {
        return self.subtract_hours(days * 24);
    }

    pub fn subtract_months(self: Datetime, months: u32) Datetime {
        if (months == 0) return self;

        var days: u32 = 0;
        var months_to_subtract = months;
        var current_year = self.years;
        var current_month = self.months;

        while (months_to_subtract > 0) {
            if (current_month == 1) {
                current_month = 12;
                current_year -= 1;
            } else {
                current_month -= 1;
            }

            days += days_in_month(current_year, current_month);
            months_to_subtract -= 1;
        }

        return self.subtract_days(days);
    }

    pub fn subtract_years(self: Datetime, years: u16) Datetime {
        if (years == 0) return self;

        var days: u32 = 0;
        var years_to_subtract = years;
        var current_year = self.years;

        while (years_to_subtract > 0) {
            current_year -= 1;
            days += days_in_year(current_year);
            years_to_subtract -= 1;
        }

        return self.subtract_days(days);
    }

    pub fn subtract(self: Datetime, time_frame: Timeframe) Datetime {
        return switch (time_frame) {
            .years => |years| self.subtract_years(years),
            .months => |months| self.subtract_months(months),
            .days => |days| self.subtract_days(days),
            .hours => |hours| self.subtract_hours(hours),
            .minutes => |minutes| self.subtract_minutes(minutes),
            .seconds => |seconds| self.subtract_seconds(seconds),
        };
    }

    pub fn compare(self: Datetime, other: Datetime) Eq {
        if (self.years < other.years) return .LT;
        if (self.years > other.years) return .GT;
        if (self.months < other.months) return .LT;
        if (self.months > other.months) return .GT;
        if (self.days < other.days) return .LT;
        if (self.days > other.days) return .GT;
        if (self.hours < other.hours) return .LT;
        if (self.hours > other.hours) return .GT;
        if (self.minutes < other.minutes) return .LT;
        if (self.minutes > other.minutes) return .GT;
        if (self.seconds < other.seconds) return .LT;
        if (self.seconds > other.seconds) return .GT;
        return .EQ;
    }

    pub fn range(allocator: Allocator, options: RangeOptions) !ArrayList(Datetime) {
        var range_list = ArrayList(Datetime).init(allocator);
        var current_datetime = options.start_date;

        while (current_datetime.compare(options.end_date) != .GT) {
            try range_list.append(current_datetime);
            current_datetime = current_datetime.add(options.step);
        }

        return range_list;
    }

    pub fn jsonStringify(self: Datetime, writer: anytype) !void {
        try writer.print("\"{}\"", .{self});
    }

    pub fn jsonParse(allocator: Allocator, scanner: anytype, _: std.json.ParseOptions) !Datetime {
        const token = try scanner.*.next();

        switch (token) {
            .string => |value| {
                return Datetime.parse(value) catch std.json.ParseFromValueError.UnexpectedToken;
            },

            .partial_string => |value| {
                const savedValue = try allocator.dupe(u8, value);
                defer allocator.free(savedValue);

                const next_token = try scanner.*.next();

                switch (next_token) {
                    .string => |next_value| {
                        const combined = try std.mem.concat(allocator, u8, &[_][]const u8{ savedValue, next_value });
                        defer allocator.free(combined);

                        return Datetime.parse(combined) catch std.json.ParseFromValueError.UnexpectedToken;
                    },
                    else => {},
                }
                return std.json.ParseFromValueError.UnexpectedToken;
            },
            else => return std.json.ParseFromValueError.UnexpectedToken,
        }
    }
};

pub fn is_leap_years(years: u16) bool {
    return years % 4 == 0 and (years % 100 != 0 or years % 400 == 0);
}

pub fn days_in_month(years: u16, months: u8) u8 {
    return switch (months) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (is_leap_years(years)) 29 else 28,
        else => @panic("Invalid month"),
    };
}

pub fn days_in_year(year: u16) u16 {
    return if (is_leap_years(year)) 366 else 365;
}

test "datetime from_timestamp" {
    // Epoch
    {
        const timestamp: i64 = 0;
        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = Datetime.from_timestamp(timestamp);

        try testing.expectEqualDeep(expected, actual);
    }

    // Specific date (2000-01-01 00:00:00)
    {
        const timestamp: i64 = 946684800;
        const expected = Datetime{
            .years = 2000,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = Datetime.from_timestamp(timestamp);
        try testing.expectEqualDeep(expected, actual);
    }

    // Leap year date (2000-02-29 00:00:00)
    {
        const timestamp: i64 = 951782400;
        const expected = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = Datetime.from_timestamp(timestamp);
        try testing.expectEqualDeep(expected, actual);
    }

    // End of 1999 (1999-12-31 23:59:59)
    {
        const timestamp: i64 = 946684799;
        const expected = Datetime{
            .years = 1999,
            .months = 12,
            .days = 31,
            .hours = 23,
            .minutes = 59,
            .seconds = 59,
        };
        const actual = Datetime.from_timestamp(timestamp);
        try testing.expectEqualDeep(expected, actual);
    }

    // Random date (2023-05-23 09:50:15)
    {
        const timestamp: i64 = 1684835415;
        const expected = Datetime{
            .years = 2023,
            .months = 5,
            .days = 23,
            .hours = 9,
            .minutes = 50,
            .seconds = 15,
        };
        const actual = Datetime.from_timestamp(timestamp);
        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime to_timestamp" {
    // Epoch
    {
        const expected: i64 = 0;
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = datetime.to_timestamp();

        try testing.expectEqualDeep(expected, actual);
    }

    // Specific date (2000-01-01 00:00:00)
    {
        const expected: i64 = 946684800;
        const datetime = Datetime{
            .years = 2000,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = datetime.to_timestamp();
        try testing.expectEqualDeep(expected, actual);
    }

    // Leap year date (2000-02-29 00:00:00)
    {
        const expected: i64 = 951782400;
        const datetime = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = datetime.to_timestamp();
        try testing.expectEqualDeep(expected, actual);
    }

    // End of 1999 (1999-12-31 23:59:59)
    {
        const expected: i64 = 946684799;
        const datetime = Datetime{
            .years = 1999,
            .months = 12,
            .days = 31,
            .hours = 23,
            .minutes = 59,
            .seconds = 59,
        };
        const actual = datetime.to_timestamp();
        try testing.expectEqualDeep(expected, actual);
    }

    // Random date (2023-05-23 09:50:15)
    {
        const expected: i64 = 1684835415;
        const datetime = Datetime{
            .years = 2023,
            .months = 5,
            .days = 23,
            .hours = 9,
            .minutes = 50,
            .seconds = 15,
        };
        const actual = datetime.to_timestamp();
        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime format" {
    // Epoch
    {
        const expected = "1970-01-01T00:00:00Z";
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        var buffer: [20]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.format(undefined, undefined, &writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }

    // Specific date (2000-01-01 00:00:00)
    {
        const expected = "2000-01-01T00:00:00Z";
        const datetime = Datetime{
            .years = 2000,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        var buffer: [20]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.format(undefined, undefined, &writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }

    // Leap year date (2000-02-29 00:00:00)
    {
        const expected = "2000-02-29T00:00:00Z";
        const datetime = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        var buffer: [20]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.format(undefined, undefined, &writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }

    // End of 1999 (1999-12-31 23:59:59)
    {
        const expected = "1999-12-31T23:59:59Z";
        const datetime = Datetime{
            .years = 1999,
            .months = 12,
            .days = 31,
            .hours = 23,
            .minutes = 59,
            .seconds = 59,
        };
        var buffer: [20]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.format(undefined, undefined, &writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }

    // Random date (2023-05-23 09:50:15)
    {
        const expected = "2023-05-23T09:50:15Z";
        const datetime = Datetime{
            .years = 2023,
            .months = 5,
            .days = 23,
            .hours = 9,
            .minutes = 50,
            .seconds = 15,
        };
        var buffer: [20]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.format(undefined, undefined, &writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }
}

test "datetime parse" {
    {
        const input = "1970-01-01T00:00:00Z";
        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = try Datetime.parse(input);

        try testing.expectEqualDeep(expected, actual);
    }

    // Specific date (2000-01-01 00:00:00)
    {
        const input = "2000-01-01T00:00:00Z";
        const expected = Datetime{
            .years = 2000,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = try Datetime.parse(input);

        try testing.expectEqualDeep(expected, actual);
    }

    // Leap year date (2000-02-29 00:00:00)
    {
        const input = "2000-02-29T00:00:00Z";
        const expected = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        const actual = try Datetime.parse(input);

        try testing.expectEqualDeep(expected, actual);
    }

    // End of 1999 (1999-12-31 23:59:59)
    {
        const input = "1999-12-31T23:59:59Z";
        const expected = Datetime{
            .years = 1999,
            .months = 12,
            .days = 31,
            .hours = 23,
            .minutes = 59,
            .seconds = 59,
        };
        const actual = try Datetime.parse(input);

        try testing.expectEqualDeep(expected, actual);
    }

    // Random date (2023-05-23 09:50:15)
    {
        const input = "2023-05-23T09:50:15Z";
        const expected = Datetime{
            .years = 2023,
            .months = 5,
            .days = 23,
            .hours = 9,
            .minutes = 50,
            .seconds = 15,
        };
        const actual = try Datetime.parse(input);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_seconds" {

    // Add seconds less than 60
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 59,
        };

        const actual = datetime.add_seconds(59);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add one minute in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 1,
            .seconds = 0,
        };

        const actual = datetime.add_seconds(60);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add one hour in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_seconds(3600);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add one day in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_seconds(86400);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add one month in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_seconds(86400 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add one year in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_seconds(86400 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_minutes" {
    // Add minutes less than 60
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 59,
            .seconds = 0,
        };

        const actual = datetime.add_minutes(59);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 hour in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 2,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_minutes(60);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 day in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_minutes(60 * 24);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 month in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_minutes(60 * 24 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_minutes(60 * 24 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_hours" {

    // Add hours less than 24
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 23,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_hours(23);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 day in hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_hours(24);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 month in hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_hours(24 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year in hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_hours(24 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_days" {
    // Add days less than in month (31)
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 31,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_days(30);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 month in days
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_days(31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year in days
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_days(365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_months" {

    // Add months less than 12
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 11,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_months(10);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year in months
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_months(12);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year in months leap year (2000-02-29T00:00:00)
    {
        const datetime = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2001,
            .months = 3,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_months(12);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add_year" {

    // Add 1 year
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_years(1);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 years on leap year
    {
        const datetime = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2001,
            .months = 3,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_years(1);

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 4 years on leap year
    {
        const datetime = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2004,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add_years(4);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime add" {

    // Add 59 seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 59,
        };

        const actual = datetime.add(.{ .seconds = 59 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 59 minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 59,
            .seconds = 0,
        };

        const actual = datetime.add(.{ .minutes = 59 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 23 hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 23,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add(.{ .hours = 23 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 364 days
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 12,
            .days = 31,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add(.{ .days = 364 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 11 months
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 12,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add(.{ .months = 11 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Add 1 year
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.add(.{ .years = 1 });

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_seconds" {
    // Subtract seconds less than 60
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 59,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(59);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract one minute in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 1,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(60);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract one hour in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(3600);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract one day in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(86400);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract one month in seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(86400 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract one year in seconds
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_seconds(86400 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_minutes" {
    // Subtract minutes less than 60
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 59,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_minutes(59);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 hour in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 2,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_minutes(60);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 day in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_minutes(60 * 24);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 month in minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_minutes(60 * 24 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year in minutes
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 1,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_minutes(60 * 24 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_hours" {
    // Subtract hours less than 24
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 23,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_hours(23);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 day in hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 2,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_hours(24);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 month in hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_hours(24 * 31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year in hours
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_hours(24 * 365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_days" {
    // Subtract days less than in month (31)
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 31,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_days(30);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 month in days
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 2,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_days(31);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year in days
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_days(365);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_months" {
    // Subtract months less than 12
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 11,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_months(10);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year in months
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_months(12);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year in months leap year (2001-03-01T00:00:00)
    {
        const datetime = Datetime{
            .years = 2001,
            .months = 3,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2000,
            .months = 3,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_months(12);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract_year" {
    // Subtract 1 year
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_years(1);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year on leap year
    {
        const datetime = Datetime{
            .years = 2001,
            .months = 3,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_years(1);

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 4 years on leap year
    {
        const datetime = Datetime{
            .years = 2004,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 2000,
            .months = 2,
            .days = 29,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract_years(4);

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime subtract" {
    // Subtract 59 seconds
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 59,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .seconds = 59 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 59 minutes
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 59,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .minutes = 59 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 23 hours
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 23,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .hours = 23 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 364 days
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 12,
            .days = 31,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .days = 364 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 11 months
    {
        const datetime = Datetime{
            .years = 1970,
            .months = 12,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .months = 11 });

        try testing.expectEqualDeep(expected, actual);
    }

    // Subtract 1 year
    {
        const datetime = Datetime{
            .years = 1971,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        const actual = datetime.subtract(.{ .years = 1 });

        try testing.expectEqualDeep(expected, actual);
    }
}

test "datetime range" {
    // Simple step of 1 difference of 10 seconds
    {
        const start_date = Datetime{};
        const end_date = start_date.add(.{ .seconds = 10 });
        const fifth_date = start_date.add(.{ .seconds = 5 });

        const options = RangeOptions{
            .start_date = start_date,
            .end_date = end_date,
            .step = .{ .seconds = 1 },
        };

        const test_range = try Datetime.range(testing.allocator, options);
        defer test_range.deinit();

        try testing.expectEqual(11, test_range.items.len);
        try testing.expectEqualDeep(start_date, test_range.items[0]);
        try testing.expectEqualDeep(fifth_date, test_range.items[5]);
        try testing.expectEqualDeep(end_date, test_range.items[10]);
    }

    // Simple step of 3 difference of 10 seconds
    {
        const start_date = Datetime{};
        const end_date = start_date.add(.{ .seconds = 10 });

        const options = RangeOptions{
            .start_date = start_date,
            .end_date = end_date,
            .step = .{ .seconds = 3 },
        };

        const test_range = try Datetime.range(testing.allocator, options);
        defer test_range.deinit();

        try testing.expectEqual(4, test_range.items.len);
        try testing.expectEqualDeep(start_date, test_range.items[0]);
    }

    // Complex step of 365 days in seconds difference of 1 year
    {
        const start_date = Datetime{};
        const end_date = start_date.add(.{ .years = 1 });

        const options = RangeOptions{
            .start_date = start_date,
            .end_date = end_date,
            .step = .{ .days = 1 },
        };

        const test_range = try Datetime.range(testing.allocator, options);
        defer test_range.deinit();

        try testing.expectEqual(366, test_range.items.len);
        try testing.expectEqualDeep(start_date, test_range.items[0]);
        try testing.expectEqualDeep(end_date, test_range.items[365]);
    }
}

test "datetime compare" {
    const datetime1 = Datetime{
        .years = 2024,
        .months = 5,
        .days = 23,
        .hours = 15,
        .minutes = 30,
        .seconds = 45,
    };

    const datetime2 = Datetime{
        .years = 2024,
        .months = 5,
        .days = 23,
        .hours = 15,
        .minutes = 30,
        .seconds = 45,
    };

    const datetime3 = Datetime{
        .years = 2023,
        .months = 5,
        .days = 23,
        .hours = 15,
        .minutes = 30,
        .seconds = 45,
    };

    const datetime4 = Datetime{
        .years = 2024,
        .months = 5,
        .days = 24,
        .hours = 15,
        .minutes = 30,
        .seconds = 45,
    };

    try std.testing.expect(datetime1.compare(datetime2) == .EQ);
    try std.testing.expect(datetime1.compare(datetime3) == .GT);
    try std.testing.expect(datetime1.compare(datetime4) == .LT);
    try std.testing.expect(datetime3.compare(datetime1) == .LT);
    try std.testing.expect(datetime4.compare(datetime1) == .GT);
}

test "datetime jsonStringify" {

    // Epoch
    {
        const expected = "\"1970-01-01T00:00:00Z\"";
        const datetime = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };
        var buffer: [22]u8 = undefined;
        var fixed_buffer = std.io.fixedBufferStream(&buffer);
        var writer = fixed_buffer.writer();

        try datetime.jsonStringify(&writer);

        try testing.expectEqualSlices(u8, expected, &buffer);
    }
}

test "datetime jsonParse" {
    // Epoch
    {
        const input = "\"1970-01-01T00:00:00Z\"";
        const expected = Datetime{
            .years = 1970,
            .months = 1,
            .days = 1,
            .hours = 0,
            .minutes = 0,
            .seconds = 0,
        };

        var scanner = std.json.Scanner.initCompleteInput(testing.allocator, input);
        defer scanner.deinit();

        const actual = try Datetime.jsonParse(testing.allocator, &scanner, .{});

        try testing.expectEqualDeep(expected, actual);
    }
}

test "is_leap_years" {
    try testing.expect(is_leap_years(2019) == false);
    try testing.expect(is_leap_years(2018) == false);
    try testing.expect(is_leap_years(2017) == false);
    try testing.expect(is_leap_years(2016) == true);
    try testing.expect(is_leap_years(2000) == true);
    try testing.expect(is_leap_years(1900) == false);
}

test "days_in_month tests" {
    // Test for months with 31 days
    try testing.expectEqual(days_in_month(2023, 1), 31);
    try testing.expectEqual(days_in_month(2023, 3), 31);
    try testing.expectEqual(days_in_month(2023, 5), 31);
    try testing.expectEqual(days_in_month(2023, 7), 31);
    try testing.expectEqual(days_in_month(2023, 8), 31);
    try testing.expectEqual(days_in_month(2023, 10), 31);
    try testing.expectEqual(days_in_month(2023, 12), 31);

    // Test for months with 30 days
    try testing.expectEqual(days_in_month(2023, 4), 30);
    try testing.expectEqual(days_in_month(2023, 6), 30);
    try testing.expectEqual(days_in_month(2023, 9), 30);
    try testing.expectEqual(days_in_month(2023, 11), 30);

    // Test for February in a common year
    try testing.expectEqual(days_in_month(2023, 2), 28);

    // Test for February in a leap year
    try testing.expectEqual(days_in_month(2024, 2), 29);

    // Test for February in a century year that is not a leap year
    try testing.expectEqual(days_in_month(1900, 2), 28);

    // Test for February in a century year that is a leap year
    try testing.expectEqual(days_in_month(2000, 2), 29);
}

test "days_in_year tests" {
    // Test for common years
    try testing.expectEqual(days_in_year(2023), 365);
    try testing.expectEqual(days_in_year(2019), 365);
    try testing.expectEqual(days_in_year(1900), 365); // Century year not a leap year

    // Test for leap years
    try testing.expectEqual(days_in_year(2024), 366);
    try testing.expectEqual(days_in_year(2000), 366); // Century year that is a leap year
    try testing.expectEqual(days_in_year(2020), 366);
    try testing.expectEqual(days_in_year(2016), 366);

    // Test for edge cases
    try testing.expectEqual(days_in_year(0), 366); // Year 0 is a leap year
    try testing.expectEqual(days_in_year(400), 366); // Year 400 is a leap year
}

const std = @import("std");
const eql = std.mem.eql;

const Error = error{
    UniqueViolation,
    SuccessfulCompletion,
    Warning,
    DynamicResultSetsReturned,
    ImplicitZeroBitPadding,
    NullValueEliminatedInSetFunction,
    PrivilegeNotGranted,
    PrivilegeNotRevoked,
    StringDataRightTruncation,
    DeprecatedFeature,
    NoData,
    NoAdditionalDynamicResultSetsReturned,
    SqlStatementNotYetComplete,
    ConnectionException,
    ConnectionDoesNotExist,
    ConnectionFailure,
    SqlclientUnableToEstablishSqlconnection,
    SqlserverRejectedEstablishmentOfSqlconnection,
    TransactionResolutionUnknown,
    ProtocolViolation,
    TriggeredActionException,
    FeatureNotSupported,
    InvalidTransactionInitiation,
    LocatorException,
    InvalidLocatorSpecification,
    InvalidGrantor,
    InvalidGrantOperation,
    InvalidRoleSpecification,
    DiagnosticsException,
    StackedDiagnosticsAccessedWithoutActiveHandler,
    CaseNotFound,
    CardinalityViolation,
    DataException,
    ArraySubscriptError,
    CharacterNotInRepertoire,
    DatetimeFieldOverflow,
    DivisionByZero,
    ErrorInAssignment,
    EscapeCharacterConflict,
    IndicatorOverflow,
    IntervalFieldOverflow,
    InvalidArgumentForLogarithm,
    InvalidArgumentForNtileFunction,
    InvalidArgumentForNthValueFunction,
    InvalidArgumentForPowerFunction,
    InvalidArgumentForWidthBucketFunction,
    InvalidCharacterValueForCast,
    InvalidDatetimeFormat,
    InvalidEscapeCharacter,
    InvalidEscapeOctet,
    InvalidEscapeSequence,
    NonstandardUseOfEscapeCharacter,
    InvalidIndicatorParameterValue,
    InvalidParameterValue,
    InvalidPrecedingOrFollowingSize,
    InvalidRegularExpression,
    InvalidRowCountInLimitClause,
    InvalidRowCountInResultOffsetClause,
    InvalidTablesampleArgument,
    InvalidTablesampleRepeat,
    InvalidTimeZoneDisplacementValue,
    InvalidUseOfEscapeCharacter,
    MostSpecificTypeMismatch,
    NullValueNotAllowed,
    NullValueNoIndicatorParameter,
    NumericValueOutOfRange,
    SequenceGeneratorLimitExceeded,
    StringDataLengthMismatch,
    SubstringError,
    TrimError,
    UnterminatedCString,
    ZeroLengthCharacterString,
    FloatingPointException,
    InvalidTextRepresentation,
    InvalidBinaryRepresentation,
    BadCopyFileFormat,
    UntranslatableCharacter,
    NotAnXmlDocument,
    InvalidXmlDocument,
    InvalidXmlContent,
    InvalidXmlComment,
    InvalidXmlProcessingInstruction,
    DuplicateJsonObjectKeyValue,
    InvalidArgumentForSqlJsonDatetimeFunction,
    InvalidJsonText,
    InvalidSqlJsonSubscript,
    MoreThanOneSqlJsonItem,
    NoSqlJsonItem,
    NonNumericSqlJsonItem,
    NonUniqueKeysInAJsonObject,
    SingletonSqlJsonItemRequired,
    SqlJsonArrayNotFound,
    SqlJsonMemberNotFound,
    SqlJsonNumberNotFound,
    SqlJsonObjectNotFound,
    TooManyJsonArrayElements,
    TooManyJsonObjectMembers,
    SqlJsonScalarRequired,
    SqlJsonItemCannotBeCastToTargetType,
    IntegrityConstraintViolation,
    RestrictViolation,
    NotNullViolation,
    ForeignKeyViolation,
    CheckViolation,
    ExclusionViolation,
    InvalidCursorState,
    InvalidTransactionState,
    ActiveSqlTransaction,
    BranchTransactionAlreadyActive,
    HeldCursorRequiresSameIsolationLevel,
    InappropriateAccessModeForBranchTransaction,
    InappropriateIsolationLevelForBranchTransaction,
    NoActiveSqlTransactionForBranchTransaction,
    ReadOnlySqlTransaction,
    SchemaAndDataStatementMixingNotSupported,
    NoActiveSqlTransaction,
    InFailedSqlTransaction,
    IdleInTransactionSessionTimeout,
    TransactionTimeout,
    InvalidSqlStatementName,
    TriggeredDataChangeViolation,
    InvalidAuthorizationSpecification,
    InvalidPassword,
    DependentPrivilegeDescriptorsStillExist,
    DependentObjectsStillExist,
    InvalidTransactionTermination,
    SqlRoutineException,
    FunctionExecutedNoReturnStatement,
    ModifyingSqlDataNotPermitted,
    ProhibitedSqlStatementAttempted,
    ReadingSqlDataNotPermitted,
    InvalidCursorName,
    ExternalRoutineException,
    ContainingSqlNotPermitted,
    ExternalRoutineInvocationException,
    InvalidSqlstateReturned,
    TriggerProtocolViolated,
    SrfProtocolViolated,
    EventTriggerProtocolViolated,
    SavepointException,
    InvalidSavepointSpecification,
    InvalidCatalogName,
    InvalidSchemaName,
    TransactionRollback,
    TransactionIntegrityConstraintViolation,
    SerializationFailure,
    StatementCompletionUnknown,
    DeadlockDetected,
    SyntaxErrorOrAccessRuleViolation,
    SyntaxError,
    InsufficientPrivilege,
    CannotCoerce,
    GroupingError,
    WindowingError,
    InvalidRecursion,
    InvalidForeignKey,
    InvalidName,
    NameTooLong,
    ReservedName,
    DatatypeMismatch,
    IndeterminateDatatype,
    CollationMismatch,
    IndeterminateCollation,
    WrongObjectType,
    GeneratedAlways,
    UndefinedColumn,
    UndefinedFunction,
    UndefinedTable,
    UndefinedParameter,
    UndefinedObject,
    DuplicateColumn,
    DuplicateCursor,
    DuplicateDatabase,
    DuplicateFunction,
    DuplicatePreparedStatement,
    DuplicateSchema,
    DuplicateTable,
    DuplicateAlias,
    DuplicateObject,
    AmbiguousColumn,
    AmbiguousFunction,
    AmbiguousParameter,
    AmbiguousAlias,
    InvalidColumnReference,
    InvalidColumnDefinition,
    InvalidCursorDefinition,
    InvalidDatabaseDefinition,
    InvalidFunctionDefinition,
    InvalidPreparedStatementDefinition,
    InvalidSchemaDefinition,
    InvalidTableDefinition,
    InvalidObjectDefinition,
    WithCheckOptionViolation,
    InsufficientResources,
    DiskFull,
    OutOfMemory,
    TooManyConnections,
    ConfigurationLimitExceeded,
    ProgramLimitExceeded,
    StatementTooComplex,
    TooManyColumns,
    TooManyArguments,
    ObjectNotInPrerequisiteState,
    ObjectInUse,
    CantChangeRuntimeParam,
    LockNotAvailable,
    UnsafeNewEnumValueUsage,
    OperatorIntervention,
    QueryCanceled,
    AdminShutdown,
    CrashShutdown,
    CannotConnectNow,
    DatabaseDropped,
    IdleSessionTimeout,
    SystemError,
    IoError,
    UndefinedFile,
    DuplicateFile,
    ConfigFileError,
    LockFileExists,
    FdwError,
    FdwColumnNameNotFound,
    FdwDynamicParameterValueNeeded,
    FdwFunctionSequenceError,
    FdwInconsistentDescriptorInformation,
    FdwInvalidAttributeValue,
    FdwInvalidColumnName,
    FdwInvalidColumnNumber,
    FdwInvalidDataType,
    FdwInvalidDataTypeDescriptors,
    FdwInvalidDescriptorFieldIdentifier,
    FdwInvalidHandle,
    FdwInvalidOptionIndex,
    FdwInvalidOptionName,
    FdwInvalidStringLengthOrBufferLength,
    FdwInvalidStringFormat,
    FdwInvalidUseOfNullPointer,
    FdwTooManyHandles,
    FdwOutOfMemory,
    FdwNoSchemas,
    FdwOptionNameNotFound,
    FdwReplyHandle,
    FdwSchemaNotFound,
    FdwTableNotFound,
    FdwUnableToCreateExecution,
    FdwUnableToCreateReply,
    FdwUnableToEstablishConnection,
    PlpgsqlError,
    RaiseException,
    NoDataFound,
    TooManyRows,
    AssertFailure,
    InternalError,
    DataCorrupted,
    IndexCorrupted,
};

pub fn code_to_error(slice: []const u8) Error {
    if (eql(u8, slice, "00000")) return Error.SuccessfulCompletion;
    if (eql(u8, slice, "01000")) return Error.Warning;
    if (eql(u8, slice, "0100C")) return Error.DynamicResultSetsReturned;
    if (eql(u8, slice, "01008")) return Error.ImplicitZeroBitPadding;
    if (eql(u8, slice, "01003")) return Error.NullValueEliminatedInSetFunction;
    if (eql(u8, slice, "01007")) return Error.PrivilegeNotGranted;
    if (eql(u8, slice, "01006")) return Error.PrivilegeNotRevoked;
    if (eql(u8, slice, "01004")) return Error.StringDataRightTruncation;
    if (eql(u8, slice, "01P01")) return Error.DeprecatedFeature;
    if (eql(u8, slice, "02000")) return Error.NoData;
    if (eql(u8, slice, "02001")) return Error.NoAdditionalDynamicResultSetsReturned;
    if (eql(u8, slice, "03000")) return Error.SqlStatementNotYetComplete;
    if (eql(u8, slice, "08000")) return Error.ConnectionException;
    if (eql(u8, slice, "08003")) return Error.ConnectionDoesNotExist;
    if (eql(u8, slice, "08006")) return Error.ConnectionFailure;
    if (eql(u8, slice, "08001")) return Error.SqlclientUnableToEstablishSqlconnection;
    if (eql(u8, slice, "08004")) return Error.SqlserverRejectedEstablishmentOfSqlconnection;
    if (eql(u8, slice, "08007")) return Error.TransactionResolutionUnknown;
    if (eql(u8, slice, "08P01")) return Error.ProtocolViolation;
    if (eql(u8, slice, "09000")) return Error.TriggeredActionException;
    if (eql(u8, slice, "0A000")) return Error.FeatureNotSupported;
    if (eql(u8, slice, "0B000")) return Error.InvalidTransactionInitiation;
    if (eql(u8, slice, "0F000")) return Error.LocatorException;
    if (eql(u8, slice, "0F001")) return Error.InvalidLocatorSpecification;
    if (eql(u8, slice, "0L000")) return Error.InvalidGrantor;
    if (eql(u8, slice, "0LP01")) return Error.InvalidGrantOperation;
    if (eql(u8, slice, "0P000")) return Error.InvalidRoleSpecification;
    if (eql(u8, slice, "0Z000")) return Error.DiagnosticsException;
    if (eql(u8, slice, "0Z002")) return Error.StackedDiagnosticsAccessedWithoutActiveHandler;
    if (eql(u8, slice, "20000")) return Error.CaseNotFound;
    if (eql(u8, slice, "21000")) return Error.CardinalityViolation;
    if (eql(u8, slice, "22000")) return Error.DataException;
    if (eql(u8, slice, "2202E")) return Error.ArraySubscriptError;
    if (eql(u8, slice, "22021")) return Error.CharacterNotInRepertoire;
    if (eql(u8, slice, "22008")) return Error.DatetimeFieldOverflow;
    if (eql(u8, slice, "22012")) return Error.DivisionByZero;
    if (eql(u8, slice, "22005")) return Error.ErrorInAssignment;
    if (eql(u8, slice, "2200B")) return Error.EscapeCharacterConflict;
    if (eql(u8, slice, "22022")) return Error.IndicatorOverflow;
    if (eql(u8, slice, "22015")) return Error.IntervalFieldOverflow;
    if (eql(u8, slice, "2201E")) return Error.InvalidArgumentForLogarithm;
    if (eql(u8, slice, "22014")) return Error.InvalidArgumentForNtileFunction;
    if (eql(u8, slice, "22016")) return Error.InvalidArgumentForNthValueFunction;
    if (eql(u8, slice, "2201F")) return Error.InvalidArgumentForPowerFunction;
    if (eql(u8, slice, "2201G")) return Error.InvalidArgumentForWidthBucketFunction;
    if (eql(u8, slice, "22018")) return Error.InvalidCharacterValueForCast;
    if (eql(u8, slice, "22007")) return Error.InvalidDatetimeFormat;
    if (eql(u8, slice, "22019")) return Error.InvalidEscapeCharacter;
    if (eql(u8, slice, "2200D")) return Error.InvalidEscapeOctet;
    if (eql(u8, slice, "22025")) return Error.InvalidEscapeSequence;
    if (eql(u8, slice, "22P06")) return Error.NonstandardUseOfEscapeCharacter;
    if (eql(u8, slice, "22010")) return Error.InvalidIndicatorParameterValue;
    if (eql(u8, slice, "22023")) return Error.InvalidParameterValue;
    if (eql(u8, slice, "22013")) return Error.InvalidPrecedingOrFollowingSize;
    if (eql(u8, slice, "2201B")) return Error.InvalidRegularExpression;
    if (eql(u8, slice, "2201W")) return Error.InvalidRowCountInLimitClause;
    if (eql(u8, slice, "2201X")) return Error.InvalidRowCountInResultOffsetClause;
    if (eql(u8, slice, "2202H")) return Error.InvalidTablesampleArgument;
    if (eql(u8, slice, "2202G")) return Error.InvalidTablesampleRepeat;
    if (eql(u8, slice, "22009")) return Error.InvalidTimeZoneDisplacementValue;
    if (eql(u8, slice, "2200C")) return Error.InvalidUseOfEscapeCharacter;
    if (eql(u8, slice, "2200G")) return Error.MostSpecificTypeMismatch;
    if (eql(u8, slice, "22004")) return Error.NullValueNotAllowed;
    if (eql(u8, slice, "22002")) return Error.NullValueNoIndicatorParameter;
    if (eql(u8, slice, "22003")) return Error.NumericValueOutOfRange;
    if (eql(u8, slice, "2200H")) return Error.SequenceGeneratorLimitExceeded;
    if (eql(u8, slice, "22026")) return Error.StringDataLengthMismatch;
    if (eql(u8, slice, "22001")) return Error.StringDataRightTruncation;
    if (eql(u8, slice, "22011")) return Error.SubstringError;
    if (eql(u8, slice, "22027")) return Error.TrimError;
    if (eql(u8, slice, "22024")) return Error.UnterminatedCString;
    if (eql(u8, slice, "2200F")) return Error.ZeroLengthCharacterString;
    if (eql(u8, slice, "22P01")) return Error.FloatingPointException;
    if (eql(u8, slice, "22P02")) return Error.InvalidTextRepresentation;
    if (eql(u8, slice, "22P03")) return Error.InvalidBinaryRepresentation;
    if (eql(u8, slice, "22P04")) return Error.BadCopyFileFormat;
    if (eql(u8, slice, "22P05")) return Error.UntranslatableCharacter;
    if (eql(u8, slice, "2200L")) return Error.NotAnXmlDocument;
    if (eql(u8, slice, "2200M")) return Error.InvalidXmlDocument;
    if (eql(u8, slice, "2200N")) return Error.InvalidXmlContent;
    if (eql(u8, slice, "2200S")) return Error.InvalidXmlComment;
    if (eql(u8, slice, "2200T")) return Error.InvalidXmlProcessingInstruction;
    if (eql(u8, slice, "22030")) return Error.DuplicateJsonObjectKeyValue;
    if (eql(u8, slice, "22031")) return Error.InvalidArgumentForSqlJsonDatetimeFunction;
    if (eql(u8, slice, "22032")) return Error.InvalidJsonText;
    if (eql(u8, slice, "22033")) return Error.InvalidSqlJsonSubscript;
    if (eql(u8, slice, "22034")) return Error.MoreThanOneSqlJsonItem;
    if (eql(u8, slice, "22035")) return Error.NoSqlJsonItem;
    if (eql(u8, slice, "22036")) return Error.NonNumericSqlJsonItem;
    if (eql(u8, slice, "22037")) return Error.NonUniqueKeysInAJsonObject;
    if (eql(u8, slice, "22038")) return Error.SingletonSqlJsonItemRequired;
    if (eql(u8, slice, "22039")) return Error.SqlJsonArrayNotFound;
    if (eql(u8, slice, "2203A")) return Error.SqlJsonMemberNotFound;
    if (eql(u8, slice, "2203B")) return Error.SqlJsonNumberNotFound;
    if (eql(u8, slice, "2203C")) return Error.SqlJsonObjectNotFound;
    if (eql(u8, slice, "2203D")) return Error.TooManyJsonArrayElements;
    if (eql(u8, slice, "2203E")) return Error.TooManyJsonObjectMembers;
    if (eql(u8, slice, "2203F")) return Error.SqlJsonScalarRequired;
    if (eql(u8, slice, "2203G")) return Error.SqlJsonItemCannotBeCastToTargetType;
    if (eql(u8, slice, "23000")) return Error.IntegrityConstraintViolation;
    if (eql(u8, slice, "23001")) return Error.RestrictViolation;
    if (eql(u8, slice, "23502")) return Error.NotNullViolation;
    if (eql(u8, slice, "23503")) return Error.ForeignKeyViolation;
    if (eql(u8, slice, "23505")) return Error.UniqueViolation;
    if (eql(u8, slice, "23514")) return Error.CheckViolation;
    if (eql(u8, slice, "23P01")) return Error.ExclusionViolation;
    if (eql(u8, slice, "24000")) return Error.InvalidCursorState;
    if (eql(u8, slice, "25000")) return Error.InvalidTransactionState;
    if (eql(u8, slice, "25001")) return Error.ActiveSqlTransaction;
    if (eql(u8, slice, "25002")) return Error.BranchTransactionAlreadyActive;
    if (eql(u8, slice, "25008")) return Error.HeldCursorRequiresSameIsolationLevel;
    if (eql(u8, slice, "25003")) return Error.InappropriateAccessModeForBranchTransaction;
    if (eql(u8, slice, "25004")) return Error.InappropriateIsolationLevelForBranchTransaction;
    if (eql(u8, slice, "25005")) return Error.NoActiveSqlTransactionForBranchTransaction;
    if (eql(u8, slice, "25006")) return Error.ReadOnlySqlTransaction;
    if (eql(u8, slice, "25007")) return Error.SchemaAndDataStatementMixingNotSupported;
    if (eql(u8, slice, "25P01")) return Error.NoActiveSqlTransaction;
    if (eql(u8, slice, "25P02")) return Error.InFailedSqlTransaction;
    if (eql(u8, slice, "25P03")) return Error.IdleInTransactionSessionTimeout;
    if (eql(u8, slice, "25P04")) return Error.TransactionTimeout;
    if (eql(u8, slice, "26000")) return Error.InvalidSqlStatementName;
    if (eql(u8, slice, "27000")) return Error.TriggeredDataChangeViolation;
    if (eql(u8, slice, "28000")) return Error.InvalidAuthorizationSpecification;
    if (eql(u8, slice, "28P01")) return Error.InvalidPassword;
    if (eql(u8, slice, "2B000")) return Error.DependentPrivilegeDescriptorsStillExist;
    if (eql(u8, slice, "2BP01")) return Error.DependentObjectsStillExist;
    if (eql(u8, slice, "2D000")) return Error.InvalidTransactionTermination;
    if (eql(u8, slice, "2F000")) return Error.SqlRoutineException;
    if (eql(u8, slice, "2F005")) return Error.FunctionExecutedNoReturnStatement;
    if (eql(u8, slice, "2F002")) return Error.ModifyingSqlDataNotPermitted;
    if (eql(u8, slice, "2F003")) return Error.ProhibitedSqlStatementAttempted;
    if (eql(u8, slice, "2F004")) return Error.ReadingSqlDataNotPermitted;
    if (eql(u8, slice, "34000")) return Error.InvalidCursorName;
    if (eql(u8, slice, "38000")) return Error.ExternalRoutineException;
    if (eql(u8, slice, "38001")) return Error.ContainingSqlNotPermitted;
    if (eql(u8, slice, "38002")) return Error.ModifyingSqlDataNotPermitted;
    if (eql(u8, slice, "38003")) return Error.ProhibitedSqlStatementAttempted;
    if (eql(u8, slice, "38004")) return Error.ReadingSqlDataNotPermitted;
    if (eql(u8, slice, "39000")) return Error.ExternalRoutineInvocationException;
    if (eql(u8, slice, "39001")) return Error.InvalidSqlstateReturned;
    if (eql(u8, slice, "39004")) return Error.NullValueNotAllowed;
    if (eql(u8, slice, "39P01")) return Error.TriggerProtocolViolated;
    if (eql(u8, slice, "39P02")) return Error.SrfProtocolViolated;
    if (eql(u8, slice, "39P03")) return Error.EventTriggerProtocolViolated;
    if (eql(u8, slice, "3B000")) return Error.SavepointException;
    if (eql(u8, slice, "3B001")) return Error.InvalidSavepointSpecification;
    if (eql(u8, slice, "3D000")) return Error.InvalidCatalogName;
    if (eql(u8, slice, "3F000")) return Error.InvalidSchemaName;
    if (eql(u8, slice, "40000")) return Error.TransactionRollback;
    if (eql(u8, slice, "40002")) return Error.TransactionIntegrityConstraintViolation;
    if (eql(u8, slice, "40001")) return Error.SerializationFailure;
    if (eql(u8, slice, "40003")) return Error.StatementCompletionUnknown;
    if (eql(u8, slice, "40P01")) return Error.DeadlockDetected;
    if (eql(u8, slice, "42000")) return Error.SyntaxErrorOrAccessRuleViolation;
    if (eql(u8, slice, "42601")) return Error.SyntaxError;
    if (eql(u8, slice, "42501")) return Error.InsufficientPrivilege;
    if (eql(u8, slice, "42846")) return Error.CannotCoerce;
    if (eql(u8, slice, "42803")) return Error.GroupingError;
    if (eql(u8, slice, "42P20")) return Error.WindowingError;
    if (eql(u8, slice, "42P19")) return Error.InvalidRecursion;
    if (eql(u8, slice, "42830")) return Error.InvalidForeignKey;
    if (eql(u8, slice, "42602")) return Error.InvalidName;
    if (eql(u8, slice, "42622")) return Error.NameTooLong;
    if (eql(u8, slice, "42939")) return Error.ReservedName;
    if (eql(u8, slice, "42804")) return Error.DatatypeMismatch;
    if (eql(u8, slice, "42P18")) return Error.IndeterminateDatatype;
    if (eql(u8, slice, "42P21")) return Error.CollationMismatch;
    if (eql(u8, slice, "42P22")) return Error.IndeterminateCollation;
    if (eql(u8, slice, "42809")) return Error.WrongObjectType;
    if (eql(u8, slice, "428C9")) return Error.GeneratedAlways;
    if (eql(u8, slice, "42703")) return Error.UndefinedColumn;
    if (eql(u8, slice, "42883")) return Error.UndefinedFunction;
    if (eql(u8, slice, "42P01")) return Error.UndefinedTable;
    if (eql(u8, slice, "42P02")) return Error.UndefinedParameter;
    if (eql(u8, slice, "42704")) return Error.UndefinedObject;
    if (eql(u8, slice, "42701")) return Error.DuplicateColumn;
    if (eql(u8, slice, "42P03")) return Error.DuplicateCursor;
    if (eql(u8, slice, "42P04")) return Error.DuplicateDatabase;
    if (eql(u8, slice, "42723")) return Error.DuplicateFunction;
    if (eql(u8, slice, "42P05")) return Error.DuplicatePreparedStatement;
    if (eql(u8, slice, "42P06")) return Error.DuplicateSchema;
    if (eql(u8, slice, "42P07")) return Error.DuplicateTable;
    if (eql(u8, slice, "42712")) return Error.DuplicateAlias;
    if (eql(u8, slice, "42710")) return Error.DuplicateObject;
    if (eql(u8, slice, "42702")) return Error.AmbiguousColumn;
    if (eql(u8, slice, "42725")) return Error.AmbiguousFunction;
    if (eql(u8, slice, "42P08")) return Error.AmbiguousParameter;
    if (eql(u8, slice, "42P09")) return Error.AmbiguousAlias;
    if (eql(u8, slice, "42P10")) return Error.InvalidColumnReference;
    if (eql(u8, slice, "42611")) return Error.InvalidColumnDefinition;
    if (eql(u8, slice, "42P11")) return Error.InvalidCursorDefinition;
    if (eql(u8, slice, "42P12")) return Error.InvalidDatabaseDefinition;
    if (eql(u8, slice, "42P13")) return Error.InvalidFunctionDefinition;
    if (eql(u8, slice, "42P14")) return Error.InvalidPreparedStatementDefinition;
    if (eql(u8, slice, "42P15")) return Error.InvalidSchemaDefinition;
    if (eql(u8, slice, "42P16")) return Error.InvalidTableDefinition;
    if (eql(u8, slice, "42P17")) return Error.InvalidObjectDefinition;
    if (eql(u8, slice, "44000")) return Error.WithCheckOptionViolation;
    if (eql(u8, slice, "53000")) return Error.InsufficientResources;
    if (eql(u8, slice, "53100")) return Error.DiskFull;
    if (eql(u8, slice, "53200")) return Error.OutOfMemory;
    if (eql(u8, slice, "53300")) return Error.TooManyConnections;
    if (eql(u8, slice, "53400")) return Error.ConfigurationLimitExceeded;
    if (eql(u8, slice, "54000")) return Error.ProgramLimitExceeded;
    if (eql(u8, slice, "54001")) return Error.StatementTooComplex;
    if (eql(u8, slice, "54011")) return Error.TooManyColumns;
    if (eql(u8, slice, "54023")) return Error.TooManyArguments;
    if (eql(u8, slice, "55000")) return Error.ObjectNotInPrerequisiteState;
    if (eql(u8, slice, "55006")) return Error.ObjectInUse;
    if (eql(u8, slice, "55P02")) return Error.CantChangeRuntimeParam;
    if (eql(u8, slice, "55P03")) return Error.LockNotAvailable;
    if (eql(u8, slice, "55P04")) return Error.UnsafeNewEnumValueUsage;
    if (eql(u8, slice, "57000")) return Error.OperatorIntervention;
    if (eql(u8, slice, "57014")) return Error.QueryCanceled;
    if (eql(u8, slice, "57P01")) return Error.AdminShutdown;
    if (eql(u8, slice, "57P02")) return Error.CrashShutdown;
    if (eql(u8, slice, "57P03")) return Error.CannotConnectNow;
    if (eql(u8, slice, "57P04")) return Error.DatabaseDropped;
    if (eql(u8, slice, "57P05")) return Error.IdleSessionTimeout;
    if (eql(u8, slice, "58000")) return Error.SystemError;
    if (eql(u8, slice, "58030")) return Error.IoError;
    if (eql(u8, slice, "58P01")) return Error.UndefinedFile;
    if (eql(u8, slice, "58P02")) return Error.DuplicateFile;
    if (eql(u8, slice, "F0000")) return Error.ConfigFileError;
    if (eql(u8, slice, "F0001")) return Error.LockFileExists;
    if (eql(u8, slice, "HV000")) return Error.FdwError;
    if (eql(u8, slice, "HV005")) return Error.FdwColumnNameNotFound;
    if (eql(u8, slice, "HV002")) return Error.FdwDynamicParameterValueNeeded;
    if (eql(u8, slice, "HV010")) return Error.FdwFunctionSequenceError;
    if (eql(u8, slice, "HV021")) return Error.FdwInconsistentDescriptorInformation;
    if (eql(u8, slice, "HV024")) return Error.FdwInvalidAttributeValue;
    if (eql(u8, slice, "HV007")) return Error.FdwInvalidColumnName;
    if (eql(u8, slice, "HV008")) return Error.FdwInvalidColumnNumber;
    if (eql(u8, slice, "HV004")) return Error.FdwInvalidDataType;
    if (eql(u8, slice, "HV006")) return Error.FdwInvalidDataTypeDescriptors;
    if (eql(u8, slice, "HV091")) return Error.FdwInvalidDescriptorFieldIdentifier;
    if (eql(u8, slice, "HV00B")) return Error.FdwInvalidHandle;
    if (eql(u8, slice, "HV00C")) return Error.FdwInvalidOptionIndex;
    if (eql(u8, slice, "HV00D")) return Error.FdwInvalidOptionName;
    if (eql(u8, slice, "HV090")) return Error.FdwInvalidStringLengthOrBufferLength;
    if (eql(u8, slice, "HV00A")) return Error.FdwInvalidStringFormat;
    if (eql(u8, slice, "HV009")) return Error.FdwInvalidUseOfNullPointer;
    if (eql(u8, slice, "HV014")) return Error.FdwTooManyHandles;
    if (eql(u8, slice, "HV001")) return Error.FdwOutOfMemory;
    if (eql(u8, slice, "HV00P")) return Error.FdwNoSchemas;
    if (eql(u8, slice, "HV00J")) return Error.FdwOptionNameNotFound;
    if (eql(u8, slice, "HV00K")) return Error.FdwReplyHandle;
    if (eql(u8, slice, "HV00Q")) return Error.FdwSchemaNotFound;
    if (eql(u8, slice, "HV00R")) return Error.FdwTableNotFound;
    if (eql(u8, slice, "HV00L")) return Error.FdwUnableToCreateExecution;
    if (eql(u8, slice, "HV00M")) return Error.FdwUnableToCreateReply;
    if (eql(u8, slice, "HV00N")) return Error.FdwUnableToEstablishConnection;
    if (eql(u8, slice, "P0000")) return Error.PlpgsqlError;
    if (eql(u8, slice, "P0001")) return Error.RaiseException;
    if (eql(u8, slice, "P0002")) return Error.NoDataFound;
    if (eql(u8, slice, "P0003")) return Error.TooManyRows;
    if (eql(u8, slice, "P0004")) return Error.AssertFailure;
    if (eql(u8, slice, "XX000")) return Error.InternalError;
    if (eql(u8, slice, "XX001")) return Error.DataCorrupted;
    if (eql(u8, slice, "XX002")) return Error.IndexCorrupted;

    @panic("Code does not match any known error");
}

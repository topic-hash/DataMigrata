//! TNS data types — Oracle wire format types.
//!
//! Reference: Oracle Call Interface Programmer's Guide, Chapter 4.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OracleDataType {
    /// `VARCHAR2`, `NVARCHAR2`
    VarChar2 = 1,
    /// `NUMBER`
    Number = 2,
    /// `INTEGER`, `INT`, `SMALLINT`
    Integer = 3,
    /// `FLOAT`, `REAL`
    Float = 4,
    /// `DATE`
    Date = 12,
    /// `RAW`, `LONG RAW`
    Raw = 23,
    /// `LONG`
    Long = 8,
    /// `ROWID`, `UROWID`
    RowId = 11,
    /// `CHAR`, `NCHAR`
    Char = 96,
    /// `BINARY_FLOAT`
    BinaryFloat = 100,
    /// `BINARY_DOUBLE`
    BinaryDouble = 101,
    /// `CLOB`, `NCLOB`
    Clob = 112,
    /// `BLOB`
    Blob = 113,
    /// `BFILE`
    BFile = 114,
    /// `TIMESTAMP`
    Timestamp = 187,
    /// `TIMESTAMP WITH TIME ZONE`
    TimestampWithTz = 188,
    /// `INTERVAL YEAR TO MONTH`
    IntervalYearToMonth = 189,
    /// `INTERVAL DAY TO SECOND`
    IntervalDayToSecond = 190,
    /// `TIMESTAMP WITH LOCAL TIME ZONE`
    TimestampWithLocalTz = 232,
}

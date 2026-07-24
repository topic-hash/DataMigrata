
-- ============================================================================
-- MSSQL ADVANCED DEMONSTRATION DATABASE
-- Complete Idempotent Deployment Script
-- Version: 2.0 - Expanded Synthetic Data Edition
-- Rows per table: 1,000 - 5,000
-- ============================================================================
-- PREREQUISITES:
--   - SQL Server 2019+ Developer Edition (recommended) or Enterprise
--   - Full-Text Search feature installed
--   - FILESTREAM feature enabled (for FileTable)
--   - Minimum 4GB RAM, 10GB disk space
-- ============================================================================

USE master;
GO

-- ============================================================================
-- STEP 1: CLEANUP (Idempotent - safe to re-run)
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MSSQL_Advanced_Demo')
BEGIN
    ALTER DATABASE MSSQL_Advanced_Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MSSQL_Advanced_Demo;
END
GO

-- ============================================================================
-- STEP 2: CREATE DATABASE WITH ENTERPRISE FEATURES
-- ============================================================================
CREATE DATABASE MSSQL_Advanced_Demo
    COLLATE SQL_Latin1_General_CP1_CI_AS
    WITH 
        TRUSTWORTHY ON,           -- Required for CLR assemblies
        DB_CHAINING ON;           -- Cross-database ownership chaining
GO

ALTER DATABASE MSSQL_Advanced_Demo SET RECOVERY FULL;
-- Note: READ_COMMITTED_SNAPSHOT is OFF because it conflicts with memory-optimized tables.
-- Memory-optimized tables require SNAPSHOT isolation level when RCS is ON.
-- ALTER DATABASE MSSQL_Advanced_Demo SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE MSSQL_Advanced_Demo SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE = ON;
ALTER DATABASE MSSQL_Advanced_Demo SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 1000
);
ALTER DATABASE MSSQL_Advanced_Demo SET COMPATIBILITY_LEVEL = 160; -- SQL 2022 (required for JSON_OBJECT)
ALTER DATABASE MSSQL_Advanced_Demo SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE MSSQL_Advanced_Demo SET AUTO_UPDATE_STATISTICS ON;
GO

-- Add MEMORY_OPTIMIZED_FILEGROUP (required for memory-optimized tables)
ALTER DATABASE MSSQL_Advanced_Demo ADD FILEGROUP MSSQL_Advanced_Demo_mod CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE MSSQL_Advanced_Demo
    ADD FILE (NAME = N'MSSQL_Advanced_Demo_mod',
               FILENAME = N'/var/opt/mssql/data/MSSQL_Advanced_Demo_mod')
    TO FILEGROUP MSSQL_Advanced_Demo_mod;
GO

-- Enable FileStream if available (for FileTable)
-- EXEC sp_configure 'filestream access level', 2;
-- RECONFIGURE;

USE MSSQL_Advanced_Demo;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
GO

-- ============================================================================
-- STEP 3: CREATE SCHEMAS
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Sales')
    EXEC('CREATE SCHEMA Sales');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'HR')
    EXEC('CREATE SCHEMA HR');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
    EXEC('CREATE SCHEMA Audit');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Archive')
    EXEC('CREATE SCHEMA Archive');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Security')
    EXEC('CREATE SCHEMA Security');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Staging')
    EXEC('CREATE SCHEMA Staging');
GO

-- ============================================================================
-- STEP 4: CREATE TABLES
-- ============================================================================

-- HR.Employees: Hierarchical employee data with XML, computed columns, rowversion
CREATE TABLE HR.Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    ManagerID INT NULL REFERENCES HR.Employees(EmployeeID),
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    Department NVARCHAR(50),
    JobTitle NVARCHAR(100),
    Salary DECIMAL(18,2),
    HireDate DATE,
    TerminationDate DATE NULL,
    IsActive AS (CASE WHEN TerminationDate IS NULL THEN 1 ELSE 0 END) PERSISTED,
    SecurityClearanceLevel INT DEFAULT 1,
    EmployeeData XML,
    ProfilePicture VARBINARY(MAX),
    RowVersion ROWVERSION,
    CreatedAt DATETIME2(0) DEFAULT SYSUTCDATETIME(),
    ModifiedAt DATETIME2(0) DEFAULT SYSUTCDATETIME()
);

-- HR.OrgChart: HIERARCHYID native type for optimized tree operations
CREATE TABLE HR.OrgChart (
    OrgNode HIERARCHYID PRIMARY KEY CLUSTERED,
    OrgLevel AS OrgNode.GetLevel(),
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    PositionTitle NVARCHAR(100),
    Department NVARCHAR(50)
);

-- Sales.Products: Product catalog with full-text support
CREATE TABLE Sales.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50),
    SubCategory NVARCHAR(50),
    BasePrice DECIMAL(18,4),
    CostPrice DECIMAL(18,4),
    Specifications NVARCHAR(MAX),
    SearchVector AS (ProductName + ' ' + ISNULL(Category, '') + ' ' + ISNULL(SubCategory, '')) PERSISTED,
    StockLevel INT DEFAULT 0,
    ReorderPoint INT DEFAULT 10,
    IsDiscontinued BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- Sales.Transactions: Temporal table with JSON, Geography, computed columns
CREATE TABLE Sales.Transactions (
    TransactionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    CustomerID INT NOT NULL,
    ProductID INT REFERENCES Sales.Products(ProductID),
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,4) NOT NULL,
    DiscountPct DECIMAL(5,4) DEFAULT 0,
    TotalAmount AS (Quantity * UnitPrice * (1 - DiscountPct)) PERSISTED,
    TransactionDate DATETIME2 DEFAULT SYSUTCDATETIME(),
    Region GEOGRAPHY,
    TransactionDetails NVARCHAR(MAX),  -- JSON data stored as NVARCHAR(MAX) for broad compatibility
    PaymentStatus NVARCHAR(20) DEFAULT 'pending',
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Sales.TransactionsHistory));

-- Sales.CustomerCache: Memory-optimized table for high-performance lookups
CREATE TABLE Sales.CustomerCache (
    CustomerID INT PRIMARY KEY NONCLUSTERED,
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100),
    RegionCode NVARCHAR(10),
    LastOrderDate DATETIME2,
    TotalSpent DECIMAL(18,2),
    OrderCount INT DEFAULT 0,
    INDEX ix_CustomerName NONCLUSTERED (CustomerName),
    INDEX ix_Region NONCLUSTERED (RegionCode)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Sales.HighSpeedLookup: Additional memory-optimized table with hash index
CREATE TABLE Sales.HighSpeedLookup (
    LookupKey INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1000000),
    DataValue NVARCHAR(200) NOT NULL,
    Category NVARCHAR(50),
    Timestamp DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    INDEX IX_Value NONCLUSTERED (DataValue)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Audit.EventLog: Audit trail with sequence
CREATE SEQUENCE Audit.LogSequence START WITH 1 INCREMENT BY 1;

CREATE TABLE Audit.EventLog (
    LogID BIGINT DEFAULT (NEXT VALUE FOR Audit.LogSequence) PRIMARY KEY,
    EventTime DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    EventType NVARCHAR(50),
    TableName NVARCHAR(100),
    RecordID NVARCHAR(100),
    OldValues NVARCHAR(MAX),
    NewValues NVARCHAR(MAX),
    ChangedBy NVARCHAR(100) DEFAULT SUSER_SNAME(),
    SessionContext NVARCHAR(MAX),
    Severity INT DEFAULT 1
);

-- Security.SensitiveData: Encrypted columns
CREATE TABLE Security.SensitiveData (
    DataID INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT REFERENCES HR.Employees(EmployeeID),
    SSN VARBINARY(256),
    CreditCard VARBINARY(256),
    BankAccount VARBINARY(256),
    SalaryEncrypted VARBINARY(256),
    ConfidentialNote NVARCHAR(MAX),
    EncryptionDate DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- Archive.OldTransactions: For partitioned view demo
CREATE TABLE Archive.OldTransactions (
    TransactionID BIGINT NOT NULL,
    Year INT NOT NULL,
    Month INT NOT NULL,
    Day INT NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    CustomerID INT,
    ProductID INT,
    RegionCode NVARCHAR(10),
    ArchiveDate DATE DEFAULT GETDATE(),
    CONSTRAINT PK_OldTransactions PRIMARY KEY (TransactionID, Year)
);

-- Archive.Documents: FileTable for document storage
-- Note: Requires FILESTREAM to be enabled at instance level
-- CREATE TABLE Archive.Documents AS FILETABLE
-- WITH (FileTable_Directory = 'DocumentStore', FileTable_Collate_Filename = SQL_Latin1_General_CP1_CI_AS);

-- Staging.ETLSource: For MERGE and ETL demonstrations
CREATE TABLE Staging.ETLSource (
    SourceID INT IDENTITY(1,1) PRIMARY KEY,
    ExternalProductID NVARCHAR(50),
    ProductName NVARCHAR(200),
    Category NVARCHAR(50),
    Price DECIMAL(18,4),
    ActionCode CHAR(1), -- I=Insert, U=Update, D=Delete
    Processed BIT DEFAULT 0,
    ImportedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- ============================================================================
-- STEP 5: CREATE PARTITION FUNCTION AND SCHEME
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_TransactionYear')
    DROP PARTITION SCHEME ps_TransactionYear;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_TransactionYear')
    DROP PARTITION FUNCTION pf_TransactionYear;
GO

CREATE PARTITION FUNCTION pf_TransactionYear (INT)
AS RANGE RIGHT FOR VALUES (2022, 2023, 2024, 2025, 2026);

CREATE PARTITION SCHEME ps_TransactionYear
AS PARTITION pf_TransactionYear ALL TO ([PRIMARY]);

CREATE TABLE Sales.PartitionedSales (
    SaleID BIGINT IDENTITY(1,1),
    SaleYear INT NOT NULL,
    SaleMonth INT NOT NULL,
    CustomerID INT,
    ProductID INT,
    Amount DECIMAL(18,2),
    Quantity INT,
    CONSTRAINT CK_SaleYear CHECK (SaleYear >= 2020 AND SaleYear <= 2030)
) ON ps_TransactionYear(SaleYear);

-- ============================================================================
-- STEP 6: CREATE FULL-TEXT CATALOG AND INDEX
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'ftCatalog')
    DROP FULLTEXT CATALOG ftCatalog;

CREATE FULLTEXT CATALOG ftCatalog AS DEFAULT;
GO

-- Full-text index will be created after data insertion

-- ============================================================================
-- STEP 7: POPULATE SYNTHETIC DATA (1,000 - 5,000 rows per table)
-- ============================================================================

-- Helper table for data generation
CREATE TABLE #Names (FirstName NVARCHAR(50), LastName NVARCHAR(50));
INSERT INTO #Names VALUES
('James','Smith'),('Maria','Garcia'),('Robert','Johnson'),('Jennifer','Williams'),('Michael','Brown'),
('Linda','Jones'),('William','Miller'),('Patricia','Davis'),('David','Rodriguez'),('Elizabeth','Martinez'),
('Richard','Hernandez'),('Susan','Lopez'),('Joseph','Gonzalez'),('Jessica','Wilson'),('Thomas','Anderson'),
('Sarah','Thomas'),('Charles','Taylor'),('Karen','Moore'),('Christopher','Jackson'),('Nancy','Martin'),
('Daniel','Lee'),('Lisa','Perez'),('Matthew','Thompson'),('Betty','White'),('Anthony','Harris'),
('Margaret','Sanchez'),('Mark','Clark'),('Sandra','Ramirez'),('Donald','Lewis'),('Ashley','Robinson'),
('Steven','Walker'),('Kimberly','Young'),('Paul','Allen'),('Emily','King'),('Andrew','Wright'),
('Donna','Scott'),('Joshua','Torres'),('Michelle','Nguyen'),('Kenneth','Hill'),('Dorothy','Flores'),
('Kevin','Green'),('Carol','Adams'),('Brian','Nelson'),('Amanda','Baker'),('George','Hall'),
('Melissa','Rivera'),('Edward','Campbell'),('Deborah','Mitchell'),('Ronald','Carter'),('Stephanie','Roberts'),
('Timothy','Gomez'),('Rebecca','Phillips'),('Jason','Evans'),('Sharon','Turner'),('Jeffrey','Diaz'),
('Laura','Parker'),('Ryan','Cruz'),('Cynthia','Edwards'),('Jacob','Collins'),('Kathleen','Reyes'),
('Gary','Stewart'),('Amy','Morris'),('Nicholas','Morales'),('Angela','Murphy'),('Eric','Cook'),
('Shirley','Rogers'),('Jonathan','Gutierrez'),('Anna','Ortiz'),('Stephen','Morgan'),('Brenda','Cooper'),
('Larry','Peterson'),('Pamela','Bailey'),('Justin','Reed'),('Emma','Kelly'),('Scott','Howard'),
('Nicole','Ramos'),('Brandon','Kim'),('Helen','Cox'),('Benjamin','Ward'),('Samantha','Richardson'),
('Samuel','Watson'),('Katherine','Brooks'),('Gregory','Chavez'),('Christine','Wood'),('Frank','James'),
('Debra','Bennett'),('Alexander','Gray'),('Rachel','Mendoza'),('Raymond','Ruiz'),('Catherine','Hughes'),
('Patrick','Price'),('Carolyn','Alvarez'),('Jack','Castillo'),('Janet','Sanders'),('Dennis','Patel'),
('Ruth','Myers'),('Jerry','Long'),('Olivia','Ross'),('Tyler','Foster'),('Mariah','Jimenez'),
('Aaron','Powell'),('Diane','Jenkins'),('Henry','Perry'),('Virginia','Russell'),('Jose','Sullivan'),
('Julie','Bell'),('Adam','Coleman'),('Joyce','Butler'),('Douglas','Henderson'),('Joan','Barnes'),
('Nathan','Gonzales'),('Evelyn','Fisher'),('Peter','Vasquez'),('Megan','Simmons'),('Zachary','Romero'),
('Gloria','Jordan'),('Walter','Patterson'),('Teresa','Alexander'),('Kyle','Hamilton'),('Hannah','Graham'),
('Harold','Reynolds'),('Sara','Griffin'),('Carl','Wallace'),('Janice','West'),('Arthur','Cole'),
('Kathryn','Hayes'),('Gerald','Bryant'),('Christina','Ellis'),('Roger','Gibson'),('Judith','Bryant'),
('Keith','Ferguson'),('Lori','Marshall'),('Jeremy','Harrison'),('Alice','Murray'),('Terry','Ford'),
('Ann','Marshall'),('Lawrence','Owens'),('Jean','McDonald'),('Sean','Harrison'),('Doris','Ruiz'),
('Christian','Woods'),('Kathy','Cole'),('Albert','West'),('Andrea','Reyes'),('Joe','Kim'),
('Marie','Watkins'),('Bryan','Palmer'),('Frances','Mills'),('Willie','Nichols'),('Denise','Grant'),
('Jesse','Knight'),('Marilyn','Ferguson'),('Ethan','Rose'),('Ruby','Stone'),('Billy','Hawkins'),
('Martha','Dunn'),('Bruce','Perkins'),('Danielle','Hudson'),('Gabriel','Spencer'),('Theresa','Gardner'),
('Logan','Stephens'),('Sally','Payne'),('Alan','Pierce'),('Lillian','Berry'),('Juan','Matthews'),
('Brittany','Arnold'),('Wayne','Wagner'),('Victoria','Willis'),('Roy','Ray'),('Diana','Watkins'),
('Ralph','Olson'),('Annie','Carroll'),('Russell','Duncan'),('Mildred','Snyder'),('Noah','Hart'),
('Kayla','Cunningham'),('Dylan','Bradley'),('Rose','Lane'),('Elijah','Andrews'),('Julia','Ruiz'),
('Austin','Harper'),('Grace','Fox'),('Caleb','Riley'),('Judy','Armstrong'),('Christian','Carpenter'),
('Beverly','Weaver'),('Mason','Greene'),('Denise','Lawrence'),('Juan','Elliott'),('Amber','Chavez'),
('Jason','Sims'),('Theresa','Austin'),('Gavin','Peters'),('Tammy','Franklin'),('Isaiah','Lawson'),
('Maureen','Fields'),('Luis','Gutierrez'),('Jane','Ryan'),('Aiden','Schmidt'),('Ellen','Carr'),
('Connor','Ortiz'),('Joanne','Wheeler'),('Evan','Chapman'),('Chelsea','Oliver'),('Cameron','Montgomery'),
('Colleen','Richards'),('Robert','Williamson'),('Tracey','Johnston'),('Alex','Banks'),('Erin','Meyer'),
('Derek','Bishop'),('Jill','McCoy'),('Corey','Howell'),('Tracy','Alvarez'),('Ian','Morrison'),
('Morgan','Hansen'),('Chase','Fernandez'),('Dana','Garza'),('Blake','Harvey'),('Kristen','Little'),
('Devin','Burton'),('Monica','Stanley'),('Oscar','George'),('Paula','Wheeler'),('Jayden','Williamson'),
('Darlene','Soto'),('Carlos','Graves'),('Joann','Sullivan'),('Jesus','Alexander'),('Colleen','Russell'),
('Max','Castro'),('Suzanne','Holland'),('Miles','Wong'),('Eleanor','Vargas'),('Leonard','Wade'),
('Clara','Maldonado'),('Wesley','Todd'),('Lucille','Calderon'),('Mitchell','Santiago'),('Anna','Sherman'),
('Dave','Quinn'),('Hilda','Blake'),('Bobby','Cervantes'),('Gwendolyn','Valdez'),('Alan','Castillo'),
('Stella','Delgado'),('Adrian','Pacheco'),('Leah','Costa'),('Colin','Bowers'),('Lucy','Nash'),
('Cole','Bennett'),('Elena','Lyons'),('Andre','Hampton'),('Joanna','Floyd'),('Trevor','Greer'),
('Marcia','Jennings'),('Erik','Mclaughlin'),('Connie','Gross'),('Mateo','Sherman'),('Darlene','Simon'),
('Seth','Ellis'),('Glenda','Reid'),('Cody','Parsons'),('Lena','Aguilar'),('Shane','Stevens'),
('Peggy','Barrett'),('Darius','Nicholson'),('Minnie','Cisneros'),('Ricardo','Tapia'),('Marsha','Fleming'),
('Pedro','Espinoza'),('Jenny','Hardin'),('Edwin','Donaldson'),('Shelby','Novak'),('Rafael','Schneider'),
('Melinda','Bradford'),('Troy','Joseph'),('Miriam','Berg'),('Calvin','Ortega'),('Velma','Brennan'),
('Clayton','Hess'),('Becky','Ericksen'),('Manuel','Klein'),('Myrtle','Yates'),('Hector','Lambert'),
('Bonnie','Hale'),('Martin','Sharp'),('Lucia','Mclean'),('Fernando','Glass'),('Naomi','Middleton'),
('Ramon','Velez'),('Carmen','Ware'),('Mario','Strong'),('Dolores','Pena'),('Marcus','Kirk'),
('Winifred','Bender'),('Ricardo','Buck'),('Antoinette','Barrera'),('Javier','Solis'),('Yolanda','Roth'),
('Sergio','Mcgee'),('Stacey','Wolf'),('Hector','Fuentes'),('Johnnie','Valencia'),('Abraham','Pitts'),
('Mae','Donovan'),('Cesar','Parrish'),('Muriel','Glover'),('Dwayne','Conway'),('Rosie','Hobbs'),
('Orlando','Herman'),('Jeannette','Norton'),('Leroy','Tate'),('Loretta','Mora'),('Raul','Morse'),
('Beatrice','Olsen'),('Marshall','Barton'),('Eula','Lindsey'),('Nelson','Huff'),('Ernestine','Gillespie'),
('Vernon','Hood'),('Lillie','Castaneda'),('Grant','Sutton'),('Celia','Franco'),('Gilbert','Doyle'),
('Verna','Krause'),('Rene','Ware'),('Mattie','Potter'),('Jaime','Booker'),('Genevieve','Horn'),
('Eddie','Barber'),('Essie','Orr'),('Ross','Stein'),('Nina','Browning'),('Freddie','Rubio'),
('Olive','Bean'),('Marlon','Sawyer'),('Agnes','Farrell'),('Lloyd','Decker'),('Billie','Wiggins'),
('Daryl','Larsen'),('Eunice','Conley'),('Neil','Gallagher'),('Francis','Brennan'),('Dewey','Villarreal'),
('Jennie','Salinas'),('Wilbur','Serrano'),('Mabel','Donaldson'),('Morris','Koch'),('Bertha','Rivas'),
('Leo','Velasquez'),('Dora','Acosta'),('Tommy','Oneal'),('Sadie','Leach'),('Byron','Madden'),
('Gertrude','Shepard'),('Omar','Booth'),('Inez','Rollins'),('Luther','Heath'),('Lula','Charles'),
('Nathaniel','Mckinney'),('Rosie','Hahn'),('Carroll','Bullock'),('Lottie','Duffy'),('Julius','Wilkins'),
('Nora','Andersen'),('Sherman','Bass'),('Reba','Tyler'),('Clifton','Blackburn'),('Fannie','Hutchinson'),
('Darnell','Merritt'),('Myra','Horne'),('Lowell','Gates'),('Johnnie','Boyer'),('Angelo','Pacheco'),
('Nettie','Buckner'),('Roderick','Compton'),('Ollie','Paul'),('Leland','Berg'),('Cora','Mcmahon'),
('Lonnie','Lindsey'),('Alberta','York'),('Dewayne','Trevino'),('Harriet','Guthrie'),('Wallace','Roy'),
('Lizzie','Vance'),('Forrest','Brandt'),('Elva','Roach'),('Myron','Sexton'),('Claudia','Kinney'),
('Alfonso','Friedman'),('Faye','Higgins'),('Jimmie','Hooper'),('Opal','Gould'),('Terrence','Brennan'),
('Ina','Savage'),('Felix','Whitehead'),('Nell','Wiley'),('Lorenzo','Munoz'),('Juanita','Krueger'),
('Randal','Kaufman'),('Cathy','Hobbs'),('Dante','Wilcox'),('Lorene','Vaughan'),('Angelo','Nolan'),
('Bobbie','Mccarty'),('Bret','Hays'),('Etta','Rosales'),('Kurt','Fischer'),('Cecelia','Becker'),
('Neal','Thornton'),('Lela','Montoya'),('Clint','Duran'),('Rena','Eldridge'),('Guadalupe','Stanley'),
('Della','Mercer'),('Robin','Winters'),('Cecilia','Brock'),('Laurence','Pruitt'),('Ola','Baxter'),
('Salvatore','Odonnell'),('Lorna','Downs'),('Curt','Macdonald'),('Jackie','Higgins'),('Rex','Baird'),
('Nadine','Grimes'),('Stuart','Sweeney'),('Rosemarie','Dickerson'),('Ted','Bentley'),('Cathleen','Rosario'),
('Willard','Vinson'),('Madeline','Mays'),('Rudy','Black'),('Marcella','English'),('Pablo','Lynn'),
('Arlene','Moon'),('Bradford','Mcclure'),('Kristine','Ashley'),('Dallas','Frederick'),('Estelle','Hays'),
('Kirk','Hurst'),('Pat','Moran'),('Rolando','Hammond'),('Lucile','Sheppard'),('Guillermo','Gates'),
('Robyn','Roach'),('Darin','Pena'),('Faith','Bender'),('Daron','Hess'),('Nola','Rosales'),
('Rocco','Brennan'),('Jodie','Wiggins'),('Rusty','Berg'),('Leticia','Klein'),('Erich','Floyd'),
('Dolly','Lambert'),('Alonzo','Parrish'),('Elsa','Novak'),('Jarrod','Schneider'),('Neva','Bradford'),
('Fabian','Joseph'),('Bettie','Berg'),('Lynne','Hale'),('Donnie','Sharp'),('Tami','Mclean'),
('Sterling','Glass'),('Lana','Middleton'),('Lamont','Velez'),('Mandy','Ware'),('Monte','Strong'),
('Rosalind','Pena'),('Darrin','Kirk'),('Lora','Bender'),('Dewayne','Buck'),('Hope','Barrera'),
('Loren','Solis'),('Nannie','Roth'),('Ellis','Mcgee'),('Iva','Wolf'),('Marlin','Fuentes'),
('Teri','Valencia'),('Gustavo','Pitts'),('Kerry','Donovan'),('Noel','Parrish'),('Patsy','Glover'),
('Thaddeus','Conway'),('Johnnie','Hobbs'),('Rolando','Herman'),('Nellie','Norton'),('Shawn','Tate'),
('Olga','Mora'),('Don','Morse'),('Leona','Olsen'),('Ollie','Barton'),('Aileen','Lindsey'),
('Garrett','Huff'),('Lenora','Gillespie'),('Cedric','Hood'),('Jana','Castaneda'),('Rudy','Sutton'),
('Marci','Franco'),('Clark','Doyle'),('Jeannie','Krause'),('Lyle','Ware'),('Dianne','Potter'),
('Rene','Booker'),('Shelia','Horn'),('Earnest','Barber'),('Doreen','Orr'),('Moses','Stein'),
('Rosalyn','Browning'),('Lamar','Rubio'),('Socorro','Bean'),('Roosevelt','Sawyer'),('Iris','Farrell'),
('Dino','Decker'),('Madelyn','Wiggins'),('Sal','Larsen'),('Imogene','Conley'),('Rodolfo','Gallagher'),
('Antonia','Brennan'),('Rashad','Villarreal'),('Elma','Salinas'),('Dorian','Serrano'),('Lynette','Donaldson'),
('Giovanni','Koch'),('Jewel','Rivas'),('Reid','Velasquez'),('Jerry','Acosta'),('Tyson','Oneal'),
('Leigh','Leach'),('Deon','Madden'),('Lourdes','Shepard'),('Daren','Booth'),('Mamie','Rollins'),
('Reynaldo','Heath'),('Jeri','Charles'),('Joesph','Mckinney'),('Merle','Hahn'),('Darius','Bullock'),
('Bennie','Duffy'),('Solomon','Wilkins'),('Aurora','Andersen'),('Jeff','Bass'),('Corinne','Tyler'),
('Claude','Blackburn'),('Alma','Hutchinson'),('Lionel','Bass'),('Shelley','Ericksen'),('Elias','Klein'),
('Noreen','Yates'),('Wilbert','Lambert'),('Effie','Hale'),('Darnell','Sharp'),('Elvira','Mclean'),
('Kendrick','Glass'),('Esperanza','Middleton'),('Rashad','Velez'),('Francisca','Ware'),('Jerald','Strong'),
('Selma','Pena'),('Toby','Kirk'),('Mona','Bender'),('Rolland','Buck'),('Gretchen','Barrera'),
('Dewayne','Solis'),('Leila','Roth'),('Micheal','Mcgee'),('Candy','Wolf'),('Cyrus','Fuentes'),
('Susie','Valencia'),('Graham','Pitts'),('Mindy','Donovan'),('Rocco','Parrish'),('Irene','Glover'),
('Brady','Conway'),('Lynne','Hobbs'),('Dante','Herman'),('Mable','Norton'),('Kurtis','Tate'),
('Rosie','Mora'),('Donovan','Morse'),('Leola','Olsen'),('Omar','Barton'),('Aida','Lindsey'),
('Garry','Huff'),('Lenore','Gillespie'),('Clement','Hood'),('Janelle','Castaneda'),('Rufus','Sutton'),
('Marcie','Franco'),('Clifford','Doyle'),('Jeannine','Krause'),('Lyman','Ware'),('Dixie','Potter'),
('Rex','Booker'),('Shelby','Horn'),('Emmett','Barber'),('Doris','Orr'),('Moshe','Stein'),
('Roslyn','Browning'),('Lanny','Rubio'),('Sondra','Bean'),('Rory','Sawyer'),('Irma','Farrell'),
('Dick','Decker'),('Madonna','Wiggins'),('Salvador','Larsen'),('Inez','Conley'),('Rod','Gallagher'),
('Antoinette','Brennan'),('Rashawn','Villarreal'),('Elvira','Salinas'),('Dorian','Serrano'),('Lynnette','Donaldson');
GO

-- Generate 5,000 employees with hierarchical structure
DECLARE @i INT = 1;
DECLARE @maxEmployees INT = 5000;
DECLARE @firstName NVARCHAR(50), @lastName NVARCHAR(50);
DECLARE @dept NVARCHAR(50), @title NVARCHAR(100);
DECLARE @salary DECIMAL(18,2), @hireDate DATE;
DECLARE @managerID INT, @clearance INT;
DECLARE @xmlData XML;

WHILE @i <= @maxEmployees
BEGIN
    SELECT TOP 1 @firstName = FirstName, @lastName = LastName 
    FROM #Names ORDER BY NEWID();

    SET @dept = (SELECT TOP 1 val FROM (VALUES 
        ('Engineering'),('Sales'),('Marketing'),('HR'),('Finance'),
        ('Operations'),('Legal'),('R&D'),('Customer Success'),('IT')
    ) AS v(val) ORDER BY NEWID());

    SET @title = (SELECT TOP 1 val FROM (VALUES 
        ('Senior Engineer'),('Engineer'),('Manager'),('Director'),('VP'),
        ('Specialist'),('Analyst'),('Consultant'),('Architect'),('Coordinator')
    ) AS v(val) ORDER BY NEWID());

    SET @salary = 45000 + (ABS(CHECKSUM(NEWID())) % 205000);
    SET @hireDate = DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 3650, '2026-07-22');
    SET @managerID = CASE 
        WHEN @i = 1 THEN NULL 
        WHEN @i <= 10 THEN 1
        ELSE (SELECT TOP 1 EmployeeID FROM HR.Employees WHERE EmployeeID < @i ORDER BY NEWID())
    END;
    SET @clearance = (ABS(CHECKSUM(NEWID())) % 5) + 1;

    SET @xmlData = '<Employee><Skills>' +
        '<Skill level="Expert">' + (SELECT TOP 1 val FROM (VALUES ('T-SQL'),('C#'),('Python'),('Data Modeling'),('Cloud Architecture')) AS v(val) ORDER BY NEWID()) + '</Skill>' +
        '<Skill level="Advanced">' + (SELECT TOP 1 val FROM (VALUES ('ETL'),('PowerShell'),('Docker'),('Kubernetes'),('Azure')) AS v(val) ORDER BY NEWID()) + '</Skill>' +
        '<Skill level="Intermediate">' + (SELECT TOP 1 val FROM (VALUES ('React'),('Angular'),('Vue'),('Node.js'),('Go')) AS v(val) ORDER BY NEWID()) + '</Skill>' +
        '</Skills><Certifications>' +
        '<Cert>' + (SELECT TOP 1 val FROM (VALUES ('MCSE'),('AWS SA'),('PMP'),('CISSP'),('Scrum Master')) AS v(val) ORDER BY NEWID()) + '</Cert>' +
        '</Certifications></Employee>';

    INSERT INTO HR.Employees (ManagerID, FullName, Email, Department, JobTitle, Salary, HireDate, EmployeeData, SecurityClearanceLevel)
    VALUES (@managerID, @firstName + ' ' + @lastName, 
            LOWER(@firstName + '.' + @lastName + CAST(@i AS VARCHAR) + '@corp.com'),
            @dept, @title, @salary, @hireDate, @xmlData, @clearance);

    SET @i = @i + 1;
END
GO

DROP TABLE #Names;
GO

-- Generate 1,000 products
DECLARE @p INT = 1;
DECLARE @productName NVARCHAR(200), @category NVARCHAR(50), @subCategory NVARCHAR(50);
DECLARE @basePrice DECIMAL(18,4), @costPrice DECIMAL(18,4);

WHILE @p <= 1000
BEGIN
    SET @category = (SELECT TOP 1 val FROM (VALUES 
        ('Software'),('Hardware'),('Services'),('Security'),('Cloud'),
        ('Analytics'),('Infrastructure'),('Development'),('Monitoring'),('Storage')
    ) AS v(val) ORDER BY NEWID());

    SET @subCategory = (SELECT TOP 1 val FROM (VALUES 
        ('Enterprise'),('Standard'),('Professional'),('Starter'),('Premium'),
        ('Basic'),('Advanced'),('Ultimate'),('Lite'),('Pro')
    ) AS v(val) ORDER BY NEWID());

    SET @productName = @subCategory + ' ' + @category + ' Solution ' + CAST(@p AS VARCHAR);
    SET @basePrice = 99.99 + (ABS(CHECKSUM(NEWID())) % 99000);
    SET @costPrice = @basePrice * 0.6;

    INSERT INTO Sales.Products (ProductName, Category, SubCategory, BasePrice, CostPrice, Specifications, StockLevel, ReorderPoint)
    VALUES (@productName, @category, @subCategory, @basePrice, @costPrice,
            'Specs: Cores=' + CAST(ABS(CHECKSUM(NEWID())) % 128 AS VARCHAR) + 
            ', RAM=' + CAST(ABS(CHECKSUM(NEWID())) % 512 AS VARCHAR) + 'GB',
            ABS(CHECKSUM(NEWID())) % 1000,
            10 + ABS(CHECKSUM(NEWID())) % 50);

    SET @p = @p + 1;
END
GO

-- Generate 5,000 transactions with geography and JSON
DECLARE @t INT = 1;
DECLARE @maxTrans INT = 5000;
DECLARE @empID INT, @custID INT, @prodID INT, @qty INT;
DECLARE @unitPrice DECIMAL(18,4), @discount DECIMAL(5,4);
DECLARE @lat FLOAT, @lon FLOAT;
DECLARE @jsonDetails NVARCHAR(MAX);
DECLARE @paymentMethods TABLE (Method NVARCHAR(20));
INSERT INTO @paymentMethods VALUES ('wire_transfer'),('credit_card'),('ach'),('sepa'),('crypto');

WHILE @t <= @maxTrans
BEGIN
    SET @empID = (SELECT TOP 1 EmployeeID FROM HR.Employees ORDER BY NEWID());
    SET @custID = 1000 + ABS(CHECKSUM(NEWID())) % 9000;
    SET @prodID = (SELECT TOP 1 ProductID FROM Sales.Products ORDER BY NEWID());
    SET @qty = 1 + ABS(CHECKSUM(NEWID())) % 50;
    SET @unitPrice = (SELECT TOP 1 BasePrice FROM Sales.Products WHERE ProductID = @prodID);
    SET @discount = CASE WHEN ABS(CHECKSUM(NEWID())) % 10 = 0 THEN 0.15 ELSE 0 END;
    SET @lat = (ABS(CHECKSUM(NEWID())) % 18000) / 100.0 - 90;
    SET @lon = (ABS(CHECKSUM(NEWID())) % 36000) / 100.0 - 180;

    SET @jsonDetails = JSON_OBJECT(
        'payment_method': (SELECT TOP 1 Method FROM @paymentMethods ORDER BY NEWID()),
        'terms': (SELECT TOP 1 val FROM (VALUES ('net_30'),('net_60'),('immediate'),('net_45')) AS v(val) ORDER BY NEWID()),
        'po_number': 'PO-' + CAST(YEAR(GETDATE()) AS VARCHAR) + '-' + RIGHT('0000' + CAST(@t AS VARCHAR), 4),
        'processed': CAST(ABS(CHECKSUM(NEWID())) % 2 AS BIT),
        'discount_code': CASE WHEN @discount > 0 THEN 'SAVE15' ELSE NULL END
    );

    INSERT INTO Sales.Transactions (EmployeeID, CustomerID, ProductID, Quantity, UnitPrice, DiscountPct, Region, TransactionDetails, PaymentStatus)
    VALUES (@empID, @custID, @prodID, @qty, @unitPrice, @discount,
            geography::Point(@lat, @lon, 4326),
            @jsonDetails,
            (SELECT TOP 1 val FROM (VALUES ('pending'),('completed'),('refunded'),('disputed')) AS v(val) ORDER BY NEWID()));

    SET @t = @t + 1;
END
GO

-- Generate 2,000 memory-optimized customer cache entries
DECLARE @c INT = 1;
DECLARE @custName NVARCHAR(100), @regionCode NVARCHAR(10);

WHILE @c <= 2000
BEGIN
    SET @custName = 'Customer ' + CAST(@c AS VARCHAR) + ' ' + 
        (SELECT TOP 1 val FROM (VALUES ('Corp'),('Ltd'),('Inc'),('LLC'),('GmbH')) AS v(val) ORDER BY NEWID());
    SET @regionCode = (SELECT TOP 1 val FROM (VALUES ('NA'),('EU'),('APAC'),('LATAM'),('MEA')) AS v(val) ORDER BY NEWID());

    INSERT INTO Sales.CustomerCache (CustomerID, CustomerName, Email, RegionCode, LastOrderDate, TotalSpent, OrderCount)
    VALUES (1000 + @c, @custName, 'contact' + CAST(@c AS VARCHAR) + '@customer.com',
            @regionCode,
            DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 365, '2026-07-22'),
            ABS(CHECKSUM(NEWID())) % 1000000,
            ABS(CHECKSUM(NEWID())) % 500);

    SET @c = @c + 1;
END
GO

-- Generate 1,000 high-speed lookup entries
DECLARE @h INT = 1;
WHILE @h <= 1000
BEGIN
    INSERT INTO Sales.HighSpeedLookup (LookupKey, DataValue, Category)
    VALUES (@h, 'LookupData_' + CAST(@h AS VARCHAR) + '_' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR),
            (SELECT TOP 1 val FROM (VALUES ('A'),('B'),('C'),('D'),('E')) AS v(val) ORDER BY NEWID()));
    SET @h = @h + 1;
END
GO

-- Generate 3,000 archive transactions (2020-2025)
DECLARE @a INT = 1;
DECLARE @archiveYear INT, @archiveMonth INT;

WHILE @a <= 3000
BEGIN
    SET @archiveYear = 2020 + ABS(CHECKSUM(NEWID())) % 6;
    SET @archiveMonth = 1 + ABS(CHECKSUM(NEWID())) % 12;

    INSERT INTO Archive.OldTransactions (TransactionID, Year, Month, Day, Amount, CustomerID, ProductID, RegionCode)
    VALUES (@a, @archiveYear, @archiveMonth, 1 + ABS(CHECKSUM(NEWID())) % 28,
            ABS(CHECKSUM(NEWID())) % 100000,
            1000 + ABS(CHECKSUM(NEWID())) % 9000,
            1 + ABS(CHECKSUM(NEWID())) % 1000,
            (SELECT TOP 1 val FROM (VALUES ('NA'),('EU'),('APAC'),('LATAM'),('MEA')) AS v(val) ORDER BY NEWID()));

    SET @a = @a + 1;
END
GO

-- Generate 2,000 partitioned sales records
DECLARE @ps INT = 1;
DECLARE @saleYear INT;

WHILE @ps <= 2000
BEGIN
    SET @saleYear = 2021 + ABS(CHECKSUM(NEWID())) % 6;

    INSERT INTO Sales.PartitionedSales (SaleYear, SaleMonth, CustomerID, ProductID, Amount, Quantity)
    VALUES (@saleYear, 1 + ABS(CHECKSUM(NEWID())) % 12,
            1000 + ABS(CHECKSUM(NEWID())) % 9000,
            1 + ABS(CHECKSUM(NEWID())) % 1000,
            ABS(CHECKSUM(NEWID())) % 50000,
            1 + ABS(CHECKSUM(NEWID())) % 100);

    SET @ps = @ps + 1;
END
GO

-- Generate 1,000 audit events
DECLARE @audit INT = 1;
DECLARE @eventTypes TABLE (EventType NVARCHAR(50));
INSERT INTO @eventTypes VALUES ('INSERT'),('UPDATE'),('DELETE'),('SELECT'),('LOGIN');

WHILE @audit <= 1000
BEGIN
    INSERT INTO Audit.EventLog (EventType, TableName, RecordID, OldValues, NewValues, Severity)
    VALUES (
        (SELECT TOP 1 EventType FROM @eventTypes ORDER BY NEWID()),
        (SELECT TOP 1 val FROM (VALUES ('HR.Employees'),('Sales.Transactions'),('Sales.Products'),('Security.SensitiveData')) AS v(val) ORDER BY NEWID()),
        CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR),
        CASE WHEN ABS(CHECKSUM(NEWID())) % 2 = 0 THEN '{"old": "value"}' ELSE NULL END,
        CASE WHEN ABS(CHECKSUM(NEWID())) % 2 = 0 THEN '{"new": "value"}' ELSE NULL END,
        1 + ABS(CHECKSUM(NEWID())) % 5
    );
    SET @audit = @audit + 1;
END
GO

-- Generate 500 ETL staging records
DECLARE @etl INT = 1;
WHILE @etl <= 500
BEGIN
    INSERT INTO Staging.ETLSource (ExternalProductID, ProductName, Category, Price, ActionCode)
    VALUES (
        'EXT-' + CAST(@etl AS VARCHAR),
        'Imported Product ' + CAST(@etl AS VARCHAR),
        (SELECT TOP 1 val FROM (VALUES ('Software'),('Hardware'),('Services')) AS v(val) ORDER BY NEWID()),
        99.99 + ABS(CHECKSUM(NEWID())) % 10000,
        (SELECT TOP 1 val FROM (VALUES ('I'),('U'),('D')) AS v(val) ORDER BY NEWID())
    );
    SET @etl = @etl + 1;
END
GO

-- ============================================================================
-- STEP 8: CREATE HIERARCHYID ORG CHART ENTRIES
-- ============================================================================
INSERT INTO HR.OrgChart (OrgNode, EmployeeID, PositionTitle, Department)
SELECT 
    HIERARCHYID::Parse('/' + CAST(EmployeeID AS VARCHAR) + '/'),
    EmployeeID,
    JobTitle,
    Department
FROM HR.Employees
WHERE ManagerID IS NULL OR EmployeeID <= 100;
GO

-- ============================================================================
-- STEP 9: CREATE FULL-TEXT INDEX (after data population)
-- ============================================================================
-- SearchVector is a computed column (not allowed as full-text key)
-- Use ProductName (unique) as the full-text key instead
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Products_ProductName' AND object_id = OBJECT_ID('Sales.Products'))
    CREATE UNIQUE INDEX UX_Products_ProductName ON Sales.Products(ProductName);
GO

CREATE FULLTEXT INDEX ON Sales.Products(ProductName, Specifications) 
KEY INDEX UX_Products_ProductName
WITH STOPLIST = SYSTEM;
GO

-- ============================================================================
-- STEP 10: ENCRYPTION SETUP
-- ============================================================================
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Str0ngP@ssw0rd!2026#Secure';

CREATE CERTIFICATE EmployeeDataCert
    WITH SUBJECT = 'Employee Sensitive Data Encryption';

CREATE SYMMETRIC KEY EmployeeSymKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE EmployeeDataCert;

OPEN SYMMETRIC KEY EmployeeSymKey
    DECRYPTION BY CERTIFICATE EmployeeDataCert;

-- Encrypt sensitive data for top 100 employees
INSERT INTO Security.SensitiveData (EmployeeID, SSN, CreditCard, BankAccount, SalaryEncrypted)
SELECT TOP 100
    EmployeeID,
    EncryptByKey(Key_GUID('EmployeeSymKey'), RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR), 3) + '-' + 
        RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 100 AS VARCHAR), 2) + '-' + 
        RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR), 4)),
    EncryptByKey(Key_GUID('EmployeeSymKey'), CAST(4000000000000000 + ABS(CHECKSUM(NEWID())) % 1000000000000000 AS VARCHAR)),
    EncryptByKey(Key_GUID('EmployeeSymKey'), CAST(100000000 + ABS(CHECKSUM(NEWID())) % 900000000 AS VARCHAR)),
    EncryptByKey(Key_GUID('EmployeeSymKey'), CAST(Salary AS VARCHAR))
FROM HR.Employees
ORDER BY EmployeeID;

CLOSE SYMMETRIC KEY EmployeeSymKey;
GO

-- ============================================================================
-- STEP 11: CREATE ADVANCED OBJECTS
-- ============================================================================

-- Indexed view (materialized)
IF OBJECT_ID('Sales.vw_ProductSummary', 'V') IS NOT NULL DROP VIEW Sales.vw_ProductSummary;
GO

CREATE VIEW Sales.vw_ProductSummary WITH SCHEMABINDING
AS
SELECT 
    p.Category,
    COUNT_BIG(*) AS ProductCount,
    SUM(p.BasePrice) AS TotalBasePrice,
    SUM(p.CostPrice) AS TotalCostPrice
FROM Sales.Products p
GROUP BY p.Category;
GO

-- Note: AVG cannot be used in indexed views; AvgBasePrice computed at query time
-- CREATE UNIQUE CLUSTERED INDEX IX_vw_ProductSummary ON Sales.vw_ProductSummary(Category);
-- If indexed view is needed, remove AvgBasePrice from select list
GO

-- Synonym
IF EXISTS (SELECT 1 FROM sys.synonyms WHERE name = 'Prod') DROP SYNONYM Prod;
CREATE SYNONYM Prod FOR Sales.Products;
GO

-- User-defined table type
IF TYPE_ID('Sales.OrderItemType') IS NOT NULL DROP TYPE Sales.OrderItemType;
CREATE TYPE Sales.OrderItemType AS TABLE (
    ProductID INT,
    Quantity INT,
    UnitPrice DECIMAL(18,4),
    DiscountPct DECIMAL(5,4) DEFAULT 0
);
GO

-- Service Broker objects
IF EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = '//Corp/Orders/OrderContract')
    DROP CONTRACT [//Corp/Orders/OrderContract];
IF EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = '//Corp/Orders/OrderRequest')
    DROP MESSAGE TYPE [//Corp/Orders/OrderRequest];
IF EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = '//Corp/Orders/OrderResponse')
    DROP MESSAGE TYPE [//Corp/Orders/OrderResponse];

CREATE MESSAGE TYPE [//Corp/Orders/OrderRequest] VALIDATION = WELL_FORMED_XML;
CREATE MESSAGE TYPE [//Corp/Orders/OrderResponse] VALIDATION = WELL_FORMED_XML;

CREATE CONTRACT [//Corp/Orders/OrderContract]
    ([//Corp/Orders/OrderRequest] SENT BY INITIATOR,
     [//Corp/Orders/OrderResponse] SENT BY TARGET);

IF EXISTS (SELECT 1 FROM sys.services WHERE name = '//Corp/Orders/OrderService')
    DROP SERVICE [//Corp/Orders/OrderService];
IF EXISTS (SELECT 1 FROM sys.service_queues WHERE name = 'OrderQueue')
    DROP QUEUE Sales.OrderQueue;

CREATE QUEUE Sales.OrderQueue;
CREATE SERVICE [//Corp/Orders/OrderService]
    ON QUEUE Sales.OrderQueue ([//Corp/Orders/OrderContract]);
GO

-- ============================================================================
-- STEP 12: CREATE SPATIAL INDEX
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'SIDX_Transactions_Region')
    DROP INDEX SIDX_Transactions_Region ON Sales.Transactions;

CREATE SPATIAL INDEX SIDX_Transactions_Region ON Sales.Transactions(Region)
USING GEOGRAPHY_GRID
WITH (
    GRIDS = (MEDIUM, MEDIUM, MEDIUM, MEDIUM),
    CELLS_PER_OBJECT = 16,
    PAD_INDEX = ON
);
GO

-- ============================================================================
-- STEP 13: CREATE COLUMNSTORE INDEX
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CS_Transactions')
    DROP INDEX IX_CS_Transactions ON Sales.Transactions;

CREATE NONCLUSTERED COLUMNSTORE INDEX IX_CS_Transactions 
ON Sales.Transactions (EmployeeID, ProductID, TransactionDate, PaymentStatus);  -- TotalAmount excluded (computed column)
GO

-- ============================================================================
-- STEP 14: ENABLE CHANGE TRACKING
-- ============================================================================
ALTER DATABASE MSSQL_Advanced_Demo SET CHANGE_TRACKING = ON (
    CHANGE_RETENTION = 2 DAYS, 
    AUTO_CLEANUP = ON
);

ALTER TABLE Sales.Products ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
ALTER TABLE HR.Employees ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
GO

-- ============================================================================
-- STEP 15: ROW-LEVEL SECURITY SETUP
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'EmployeeFilterPolicy')
    DROP SECURITY POLICY Security.EmployeeFilterPolicy;
IF OBJECT_ID('Security.fn_securitypredicate', 'IF') IS NOT NULL
    DROP FUNCTION Security.fn_securitypredicate;
GO

CREATE FUNCTION Security.fn_securitypredicate(@EmployeeID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_securitypredicate_result
WHERE 
    @EmployeeID = CAST(SESSION_CONTEXT(N'UserEmployeeID') AS INT)
    OR IS_MEMBER('db_ManagerRole') = 1
    OR CAST(SESSION_CONTEXT(N'UserEmployeeID') AS INT) IN (
        SELECT ManagerID FROM HR.Employees WHERE EmployeeID = @EmployeeID
    );
GO

CREATE SECURITY POLICY Security.EmployeeFilterPolicy
    ADD FILTER PREDICATE Security.fn_securitypredicate(EmployeeID)
        ON HR.Employees,
    ADD BLOCK PREDICATE Security.fn_securitypredicate(EmployeeID)
        ON HR.Employees AFTER INSERT
WITH (STATE = ON, SCHEMABINDING = ON);
GO

-- ============================================================================
-- STEP 16: DYNAMIC DATA MASKING
-- ============================================================================
ALTER TABLE HR.Employees
ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');

ALTER TABLE HR.Employees
ALTER COLUMN Salary ADD MASKED WITH (FUNCTION = 'default()');
GO

-- ============================================================================
-- VERIFICATION
-- ============================================================================
SELECT 
    'HR.Employees' AS [TableName], COUNT(*) AS [RowCount] FROM HR.Employees
UNION ALL SELECT 'Sales.Products', COUNT(*) FROM Sales.Products
UNION ALL SELECT 'Sales.Transactions', COUNT(*) FROM Sales.Transactions
UNION ALL SELECT 'Sales.TransactionsHistory', COUNT(*) FROM Sales.TransactionsHistory
UNION ALL SELECT 'Sales.CustomerCache', COUNT(*) FROM Sales.CustomerCache
UNION ALL SELECT 'Sales.HighSpeedLookup', COUNT(*) FROM Sales.HighSpeedLookup
UNION ALL SELECT 'Archive.OldTransactions', COUNT(*) FROM Archive.OldTransactions
UNION ALL SELECT 'Sales.PartitionedSales', COUNT(*) FROM Sales.PartitionedSales
UNION ALL SELECT 'Audit.EventLog', COUNT(*) FROM Audit.EventLog
UNION ALL SELECT 'Staging.ETLSource', COUNT(*) FROM Staging.ETLSource
UNION ALL SELECT 'Security.SensitiveData', COUNT(*) FROM Security.SensitiveData
UNION ALL SELECT 'HR.OrgChart', COUNT(*) FROM HR.OrgChart
ORDER BY TableName;
GO

PRINT '============================================================';
PRINT 'DATABASE MSSQL_Advanced_Demo DEPLOYED SUCCESSFULLY';
PRINT '============================================================';
PRINT 'Total Tables: 12';
PRINT 'Total Rows: ~20,000+';
PRINT 'Features Enabled: Temporal, Spatial, In-Memory, Columnstore,';
PRINT '  Full-Text, Encryption, RLS, Data Masking, Change Tracking,';
PRINT '  Service Broker, Partitioning, HIERARCHYID';
PRINT '============================================================';
GO

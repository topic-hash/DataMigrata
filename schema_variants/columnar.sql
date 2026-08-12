-- Schema Variant B: Columnar Optimized (LOB side-tables, dictionary-friendly types)
-- LOB columns (XML, geography) moved to side-tables; main table has reference keys

CREATE TABLE IF NOT EXISTS hr_employees (
  "EmployeeID" INTEGER,
  "ManagerID" INTEGER,
  "FullName" VARCHAR(200) NOT NULL,
  "Email" VARCHAR(200),
  "Department" VARCHAR(100),
  "JobTitle" VARCHAR(200),
  "Salary" DECIMAL(18, 2),
  "HireDate" DATE,
  "TerminationDate" DATE,
  "IsActive" BOOLEAN,
  "SecurityClearanceLevel" INTEGER,
  "EmployeeData_id" INTEGER,
  PRIMARY KEY (EmployeeID)
);

CREATE TABLE IF NOT EXISTS hr_employees_lob (
  "row_id" INTEGER PRIMARY KEY,
  "EmployeeData" TEXT
);

CREATE TABLE IF NOT EXISTS hr_orgchart (
  "OrgNode" TEXT,
  "OrgLevel" INTEGER,
  "EmployeeID" INTEGER,
  "PositionTitle" VARCHAR(200),
  "Department" VARCHAR(100),
  PRIMARY KEY (OrgNode)
);

CREATE TABLE IF NOT EXISTS sales_transactions (
  "TransactionID" BIGINT,
  "EmployeeID" INTEGER,
  "CustomerID" INTEGER NOT NULL,
  "ProductID" INTEGER,
  "Quantity" INTEGER NOT NULL,
  "UnitPrice" DECIMAL(18, 4) NOT NULL,
  "DiscountPct" DECIMAL(5, 4),
  "TotalAmount" DECIMAL(17, 2),
  "TransactionDate" TIMESTAMP,
  "Region_id" INTEGER,
  "TransactionDetails" JSON,
  "PaymentStatus" VARCHAR(40),
  "ValidFrom" TIMESTAMP NOT NULL,
  "ValidTo" TIMESTAMP NOT NULL,
  PRIMARY KEY (TransactionID)
);

CREATE TABLE IF NOT EXISTS sales_transactions_lob (
  "row_id" INTEGER PRIMARY KEY,
  "Region" TEXT
);

CREATE TABLE IF NOT EXISTS sales_products (
  "ProductID" INTEGER,
  "ProductName" VARCHAR(400) NOT NULL,
  "Category" VARCHAR(100),
  "BasePrice" DECIMAL(18, 4),
  "CostPrice" DECIMAL(18, 4),
  "StockLevel" INTEGER,
  "IsDiscontinued" BOOLEAN,
  PRIMARY KEY (ProductID)
);

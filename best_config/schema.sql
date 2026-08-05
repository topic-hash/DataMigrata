-- Schema Variant C: Pre-computed (materialized paths, cached hierarchies, bounding boxes)
-- Adds auxiliary columns for pre-computed values

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
  "EmployeeData" TEXT,
  "materialized_path" TEXT,
  "depth" INTEGER,
  PRIMARY KEY (EmployeeID)
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
  "Region" TEXT,
  "TransactionDetails" JSON,
  "PaymentStatus" VARCHAR(40),
  "ValidFrom" TIMESTAMP NOT NULL,
  "ValidTo" TIMESTAMP NOT NULL,
  "bbox_lat" DOUBLE,
  "bbox_lon" DOUBLE,
  PRIMARY KEY (TransactionID)
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

-- Pre-computed distance table for op 31
CREATE TABLE IF NOT EXISTS sales_transaction_distances (
  "FromTransactionID" BIGINT,
  "ToTransactionID" BIGINT,
  "DistanceKm" DOUBLE,
  PRIMARY KEY (FromTransactionID, ToTransactionID)
);

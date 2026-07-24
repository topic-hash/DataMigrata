/**
 * OracleSQL.g4 — PoC grammar for parsing Oracle SQL dialect.
 *
 * Covers:
 *   - SELECT with CONNECT BY, PRIOR, START WITH, LEVEL, ROWNUM
 *   - DECODE, NVL, NVL2, SYSDATE, ADD_MONTHS, TO_DATE, TO_CHAR, TO_NUMBER
 *   - (+) Oracle outer-join syntax
 *   - FROM DUAL
 *   - PL/SQL blocks: BEGIN...END with DECLARE, IF/ELSIF/ELSE, loops
 *   - INSERT, UPDATE, DELETE, CREATE, ALTER, MERGE, COMMIT
 *
 * This is a focused subset — NOT a complete Oracle grammar.
 */
grammar OracleSQL;

// =====================================================================
//  PARSER RULES
// =====================================================================

sqlScript
    : (sqlStatement SEMI?)* EOF
    ;

sqlStatement
    : selectStatement
    | insertStatement
    | updateStatement
    | deleteStatement
    | createStatement
    | alterStatement
    | mergeStatement
    | commitStatement
    | plsqlBlock
    ;

// ---------------------------------------------------------------------
//  SELECT
// ---------------------------------------------------------------------

selectStatement
    : SELECT (DISTINCT | ALL)? selectList
      FROM tableSources
      (WHERE expr)?
      hierarchicalClause?
      (GROUP BY expr (COMMA expr)*)?
      (HAVING expr)?
      (ORDER BY orderItem (COMMA orderItem)*)?
    ;

selectList
    : selectItem (COMMA selectItem)*
    ;

selectItem
    : STAR
    | identifier DOT STAR
    | expr (AS? identifier)?
    ;

tableSources
    : tableSource (COMMA tableSource)*
    ;

tableSource
    : tableName (AS? identifier)?
    ;

hierarchicalClause
    : CONNECT BY NOCYCLE? expr
      (START WITH expr)?
    ;

orderItem
    : expr (ASC | DESC)? (NULLS (FIRST | LAST))?
    ;

// ---------------------------------------------------------------------
//  INSERT
// ---------------------------------------------------------------------

insertStatement
    : INSERT INTO tableName
      (LPAREN identifier (COMMA identifier)* RPAREN)?
      VALUES LPAREN expr (COMMA expr)* RPAREN
    ;

// ---------------------------------------------------------------------
//  UPDATE
// ---------------------------------------------------------------------

updateStatement
    : UPDATE tableName
      SET assignment (COMMA assignment)*
      (WHERE expr)?
    ;

assignment
    : columnRef EQ expr
    ;

// ---------------------------------------------------------------------
//  DELETE
// ---------------------------------------------------------------------

deleteStatement
    : DELETE FROM tableName
      (WHERE expr)?
    ;

// ---------------------------------------------------------------------
//  CREATE
// ---------------------------------------------------------------------

createStatement
    : CREATE (OR REPLACE)?
      ( TABLE tableName LPAREN columnDef (COMMA columnDef)* RPAREN
      | INDEX identifier ON tableName LPAREN identifier (COMMA identifier)* RPAREN
      | VIEW identifier AS selectStatement
      | PROCEDURE identifier AS plsqlBlock
      | FUNCTION identifier LPAREN RPAREN RETURN dataType AS plsqlBlock
      | TRIGGER identifier (BEFORE | AFTER) triggerDmlEvent ON tableName
        (FOR EACH ROW)? (plsqlBlock | BEGIN SEMI END SEMI)
      )
    ;

triggerDmlEvent
    : INSERT
    | UPDATE
    | DELETE
    ;

columnDef
    : identifier dataType columnConstraint*
    ;

columnConstraint
    : NOT NULL
    | (PRIMARY | UNIQUE) KEY
    | DEFAULT expr
    | CHECK LPAREN expr RPAREN
    ;

dataType
    : VARCHAR2 LPAREN NUM_LIT RPAREN
    | NUM_TYPE (LPAREN NUM_LIT (COMMA NUM_LIT)? RPAREN)?
    | DATE
    | TIMESTAMP (LPAREN NUM_LIT RPAREN)? (WITH TIME_KW ZONE_KW)?
    | CHAR LPAREN NUM_LIT RPAREN
    | CLOB
    | BLOB
    ;

// ---------------------------------------------------------------------
//  ALTER
// ---------------------------------------------------------------------

alterStatement
    : ALTER TABLE tableName
      ( ADD    LPAREN columnDef (COMMA columnDef)* RPAREN
      | DROP    LPAREN identifier RPAREN
      | MODIFY  LPAREN columnDef (COMMA columnDef)* RPAREN
      )
    ;

// ---------------------------------------------------------------------
//  MERGE
// ---------------------------------------------------------------------

mergeStatement
    : MERGE INTO tableName (AS? identifier)?
      USING tableSource
      ON expr
      mergeUpdateClause
      mergeInsertClause
    ;

mergeUpdateClause
    : WHEN MATCHED THEN UPDATE SET assignment (COMMA assignment)*
    ;

mergeInsertClause
    : WHEN NOT MATCHED THEN INSERT
      (LPAREN identifier (COMMA identifier)* RPAREN)?
      VALUES LPAREN expr (COMMA expr)* RPAREN
    ;

// ---------------------------------------------------------------------
//  COMMIT
// ---------------------------------------------------------------------

commitStatement
    : COMMIT (WORK)?
    ;

// ---------------------------------------------------------------------
//  PL/SQL BLOCK
// ---------------------------------------------------------------------

plsqlBlock
    : (DECLARE variableDecls)?
      BEGIN plsqlBody END SEMI
    ;

variableDecls
    : variableDecl (SEMI variableDecl)* SEMI
    ;

variableDecl
    : identifier dataType (NOT NULL)? (ASSIGN expr | DEFAULT expr)?
    ;

plsqlBody
    : plsqlStatement (SEMI plsqlStatement)* SEMI?
    ;

plsqlStatement
    : selectIntoStatement
    | selectStatement
    | insertStatement
    | updateStatement
    | deleteStatement
    | mergeStatement
    | commitStatement
    | ifStatement
    | loopStatement
    | plsqlAssignment
    | NULL
    | RETURN expr?
    | EXIT (identifier)? (WHEN expr)?
    | RAISE
    ;

selectIntoStatement
    : SELECT (DISTINCT | ALL)? selectList
      INTO identifier (COMMA identifier)*
      FROM tableSources
      (WHERE expr)?
      hierarchicalClause?
      (GROUP BY expr (COMMA expr)*)?
      (HAVING expr)?
      (ORDER BY orderItem (COMMA orderItem)*)?
    ;

plsqlAssignment
    : identifier ASSIGN expr
    ;

ifStatement
    : IF expr THEN plsqlBody
      (ELSIF expr THEN plsqlBody)*
      (ELSE plsqlBody)?
      END IF
    ;

loopStatement
    : LOOP plsqlBody END LOOP
    | WHILE expr LOOP plsqlBody END LOOP
    | FOR identifier IN (REVERSE)? expr DOT DOT expr
      LOOP plsqlBody END LOOP
    ;

// =====================================================================
//  EXPRESSIONS  (ANTLR4 left-recursive operator-precedence)
// =====================================================================

expr
    : expr OR expr
    | expr AND expr
    | NOT expr
    | expr compOp expr
    | expr IS NOT? NULL
    | expr NOT? BETWEEN expr AND expr
    | expr NOT? IN LPAREN (expr (COMMA expr)*) RPAREN
    | expr NOT? IN LPAREN selectStatement RPAREN
    | expr NOT? LIKE expr (ESCAPE expr)?
    | expr PLUS  expr
    | expr MINUS expr
    | expr STAR  expr
    | expr SLASH expr
    | expr PERCENT expr
    | expr PIPE_PIPE expr
    | PLUS expr
    | MINUS expr
    | PRIOR expr
    | primary
    ;

primary
    : LPAREN expr RPAREN
    | LPAREN selectStatement RPAREN
    | NVL        LPAREN expr COMMA expr RPAREN
    | NVL2       LPAREN expr COMMA expr COMMA expr RPAREN
    | DECODE     LPAREN expr (COMMA expr)* RPAREN
    | TO_DATE    LPAREN expr (COMMA expr)? RPAREN
    | TO_CHAR    LPAREN expr (COMMA expr)? RPAREN
    | TO_NUMBER  LPAREN expr (COMMA expr)? RPAREN
    | ADD_MONTHS LPAREN expr COMMA expr RPAREN
    | SYSDATE
    | LEVEL
    | ROWNUM
    | CASE (expr)? (WHEN expr THEN expr)+ (ELSE expr)? END
    | EXISTS LPAREN selectStatement RPAREN
    | literal
    | bindVariable
    | identifier LPAREN (STAR | expr (COMMA expr)*)? RPAREN
    | columnRef outerJoin?
    ;

outerJoin
    : LPAREN PLUS RPAREN
    ;

literal
    : STRING
    | NUM_LIT
    | NULL
    | TRUE
    | FALSE
    | DATE_STRING
    ;

bindVariable
    : COLON identifier
    | COLON NUM_LIT
    ;

columnRef
    : identifier (DOT identifier)*
    ;

// =====================================================================
//  IDENTIFIERS  &  UTILITIES
// =====================================================================

identifier
    : IDENT
    | QUOTED_IDENT
    | nonReserved
    ;

tableName
    : identifier (DOT identifier)?
    ;

/**
 * Keywords that may also serve as identifiers.  Only lists words that
 * are already defined as separate lexer tokens and that we expect to
 * appear as identifiers in realistic Oracle SQL.
 */
nonReserved
    : DATE
    | SET
    | ADD
    | KEY
    | INDEX
    | VIEW
    | PROCEDURE
    | FUNCTION
    | TRIGGER
    | PACKAGE
    | WORK
    | REPLACE
    | MATCHED
    | NOCYCLE
    | ASC
    | DESC
    | NULLS
    | FIRST
    | LAST
    | DEFAULT
    | BEFORE
    | AFTER
    | CHECK
    | TIME_KW
    | ZONE_KW
    | NUM_TYPE
    | TIMESTAMP
    | COMMIT
    | START
    | DUAL_KW
    | ROW
    | LEVEL
    | ROWNUM
    | YEAR_KW
    | MONTH_KW
    | DAY_KW
    | HOUR_KW
    | MINUTE_KW
    | SECOND_KW
    ;

compOp
    : EQ
    | NEQ
    | LT
    | GT
    | LTE
    | GTE
    ;

// =====================================================================
//  LEXER RULES
// =====================================================================

// --- SQL Keywords ---

SELECT    : S E L E C T ;
DISTINCT  : D I S T I N C T ;
ALL       : A L L ;
FROM      : F R O M ;
WHERE     : W H E R E ;
AND       : A N D ;
OR        : O R ;
NOT       : N O T ;
AS        : A S ;
IN        : I N ;
LIKE      : L I K E ;
BETWEEN   : B E T W E E N ;
IS        : I S ;
NULL      : N U L L ;
TRUE      : T R U E ;
FALSE     : F A L S E ;
EXISTS    : E X I S T S ;

INSERT    : I N S E R T ;
INTO      : I N T O ;
VALUES    : V A L U E S ;
UPDATE    : U P D A T E ;
SET       : S E T ;
DELETE    : D E L E T E ;

CREATE    : C R E A T E ;
ALTER     : A L T E R ;
DROP      : D R O P ;
ADD       : A D D ;
MODIFY    : M O D I F Y ;
REPLACE   : R E P L A C E ;
TABLE     : T A B L E ;
INDEX     : I N D E X ;
VIEW      : V I E W ;
TRIGGER   : T R I G G E R ;
PROCEDURE : P R O C E D U R E ;
FUNCTION  : F U N C T I O N ;
PACKAGE   : P A C K A G E ;

MERGE     : M E R G E ;
USING     : U S I N G ;
ON        : O N ;
WHEN      : W H E N ;
MATCHED   : M A T C H E D ;
THEN      : T H E N ;
FOR       : F O R ;
EACH      : E A C H ;
ROW       : R O W ;
BEFORE    : B E F O R E ;
AFTER     : A F T E R ;

COMMIT    : C O M M I T ;
WORK      : W O R K ;

BEGIN     : B E G I N ;
END       : E N D ;
DECLARE   : D E C L A R E ;
IF        : I F ;
ELSIF     : E L S I F ;
ELSE      : E L S E ;
LOOP      : L O O P ;
WHILE     : W H I L E ;
REVERSE   : R E V E R S E ;
RETURN    : R E T U R N ;
EXIT      : E X I T ;
RAISE     : R A I S E ;
CASE      : C A S E ;
DEFAULT   : D E F A U L T ;
CHECK     : C H E C K ;
PRIMARY   : P R I M A R Y ;
UNIQUE    : U N I Q U E ;
KEY       : K E Y ;
WITH      : W I T H ;

// --- Hierarchical query ---
CONNECT   : C O N N E C T ;
BY        : B Y ;
PRIOR     : P R I O R ;
START     : S T A R T ;
NOCYCLE   : N O C Y C L E ;

// --- Pseudo-columns ---
LEVEL     : L E V E L ;
ROWNUM    : R O W N U M ;

// --- Oracle built-in functions ---
DECODE     : D E C O D E ;
NVL        : N V L ;
NVL2       : N V L '2' ;
SYSDATE    : S Y S D A T E ;
ADD_MONTHS : A D D '_' M O N T H S ;
TO_DATE    : T O '_' D A T E ;
TO_CHAR    : T O '_' C H A R ;
TO_NUMBER  : T O '_' N U M B E R ;
DATE       : D A T E ;

// --- Data types ---
VARCHAR2  : V A R C H A R '2' ;
NUM_TYPE  : N U M B E R ;
TIMESTAMP : T I M E S T A M P ;
CHAR      : C H A R ;
CLOB      : C L O B ;
BLOB      : B L O B ;

// --- WITH TIME ZONE (avoid conflict with keyword 'TIME') ---
TIME_KW   : T I M E ;
ZONE_KW   : Z O N E ;

// --- Group / Order ---
GROUP     : G R O U P ;
ORDER     : O R D E R ;
HAVING    : H A V I N G ;
ASC       : A S C ;
DESC      : D E S C ;
NULLS     : N U L L S ;
FIRST     : F I R S T ;
LAST      : L A S T ;

// --- INTERVAL parts (avoid conflicts) ---
YEAR_KW   : Y E A R ;
MONTH_KW  : M O N T H ;
DAY_KW    : D A Y ;
HOUR_KW   : H O U R ;
MINUTE_KW : M I N U T E ;
SECOND_KW : S E C O N D ;
ESCAPE    : E S C A P E ;

// --- DUAL table ---
DUAL_KW   : D U A L ;

// --- Literals ---
STRING
    : '\'' ( ~'\'' | '\'\'' )* '\''
    ;

NUM_LIT
    : DIGIT+ (DOT DIGIT+)?
    | DOT DIGIT+
    ;

DATE_STRING
    : DATE STRING
    ;

// --- Identifiers ---
IDENT
    : LETTER (LETTER | DIGIT | '_' | '$' | '#')*
    ;

QUOTED_IDENT
    : '"' (~'"' | '""')* '"'
    ;

// --- Parentheses & Operators ---
LPAREN    : '(' ;
RPAREN    : ')' ;
EQ        : '=' ;
NEQ       : '!=' | '<>' | '^=' ;
LT        : '<' ;
GT        : '>' ;
LTE       : '<=' ;
GTE       : '>=' ;
PLUS      : '+' ;
MINUS     : '-' ;
STAR      : '*' ;
SLASH     : '/' ;
PERCENT   : '%' ;
PIPE_PIPE : '||' ;
DOT       : '.' ;
COMMA     : ',' ;
SEMI      : ';' ;
COLON     : ':' ;
ASSIGN    : ':=' ;

// --- Fragment helpers ---
fragment LETTER : [a-zA-Z] ;
fragment DIGIT  : [0-9] ;

// Case-insensitive letter fragments
fragment A : [aA] ; fragment B : [bB] ; fragment C : [cC] ;
fragment D : [dD] ; fragment E : [eE] ; fragment F : [fF] ;
fragment G : [gG] ; fragment H : [hH] ; fragment I : [iI] ;
fragment J : [jJ] ; fragment K : [kK] ; fragment L : [lL] ;
fragment M : [mM] ; fragment N : [nN] ; fragment O : [oO] ;
fragment P : [pP] ; fragment Q : [qQ] ; fragment R : [rR] ;
fragment S : [sS] ; fragment T : [tT] ; fragment U : [uU] ;
fragment V : [vV] ; fragment W : [wW] ; fragment X : [xX] ;
fragment Y : [yY] ; fragment Z : [zZ] ;

// --- Whitespace & Comments ---
WS
    : [ \t\r\n\u000C]+ -> skip
    ;

LINE_COMMENT
    : '--' ~[\r\n]* -> skip
    ;

BLOCK_COMMENT
    : '/*' .*? '*/' -> skip
    ;

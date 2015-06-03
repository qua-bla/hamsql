module Sql where

--import Option
import Parser.Basic
import Utils

--import Data.Maybe
--import Data.List
import Data.String.Utils (replace)

afterDelete :: SqlStatement -> Bool
afterDelete (SqlStmt t _ _) = f t
  where
      f :: SqlStatementType -> Bool
      
      f SqlCreateSchema = True
      f SqlRoleMembership = True
      f SqlCreateFunction = True
      f SqlCreatePrimaryKeyConstr = True
      f SqlCreateUniqueConstr = True
      f SqlCreateForeignKeyConstr = True
      f SqlCreateCheckConstr = True
      f SqlAddDefault = True
      f SqlPriv = True
      f SqlComment = True
      f _ = False
afterDelete _ = False

-- SQL statements

data SqlStatement =
  SqlStmt SqlStatementType SqlName String |
  SqlStmtEmpty
  deriving (Show)

data SqlStatementType = 
  SqlDropDatabase |
  SqlCreateDatabase |
  SqlPreInstall |
  SqlDropRole |
  SqlCreateRole |
  SqlRoleMembership |
  SqlCreateSchema |
  SqlCreateDomain |
  SqlCreateType |
  -- DROP CONSTRAINTS
  SqlDropTableConstraint |
  SqlDropDomainConstraint |
  -- DROP FUNCTION
  SqlDropColumn |
  SqlDropTable |
  SqlDropFunction |
  -- SEQUENCE
  SqlCreateSequence |
  -- TABLE
  SqlCreateTable |
  SqlAddColumn |
  SqlAlterTable |
  SqlDropColumnDefault |
  SqlAlterColumn |
  SqlAddTableContraint |
  -- ALTER SEQUENCE
  SqlAlterSequence |
  -- FUNCTION
  SqlDropDomain |
  SqlDropType |
  SqlCreateFunction |
  SqlInherit |
  SqlCreatePrimaryKeyConstr |
  SqlCreateUniqueConstr |
  SqlCreateForeignKeyConstr |
  SqlCreateCheckConstr |
  SqlAddDefault |
  SqlPriv |
  SqlComment |
  SqlUnclassified |
  SqlPostInstall
    deriving (Eq, Ord, Show)

instance Eq SqlStatement where
  (==) (SqlStmt t1 n1 _) (SqlStmt t2 n2 _) = t1 == t2 && n1 == n2
  
  (==) SqlStmtEmpty SqlStmtEmpty = True
  (==) _ SqlStmtEmpty = False
  (==) SqlStmtEmpty _ = False

instance Ord SqlStatement where
  (<=) (SqlStmt t1 _ _) (SqlStmt t2 _ _) = t1 <= t2
  
  (<=) SqlStmtEmpty SqlStmtEmpty = True
  (<=) SqlStmtEmpty _ = False
  (<=) _ SqlStmtEmpty = True
  
  
typeEq :: SqlStatementType -> SqlStatement -> Bool
typeEq t1 (SqlStmt t2 _ _) = t1 == t2
typeEq _ _ = False

stmtsFilterExecutable :: [SqlStatement] -> [SqlStatement]
stmtsFilterExecutable = filter executable
  where
    executable SqlStmtEmpty = False
    executable _ = True

statementTermin :: String
statementTermin = ";\n"

replacesTypeOf :: SqlStatementType -> SqlStatement -> SqlStatement
replacesTypeOf t (SqlStmt _ x y) = SqlStmt t x y

instance SqlCode SqlStatement where
  toSql (SqlStmtEmpty) = ""
  toSql (SqlStmt SqlPreInstall _ xs) = xs ++ "\n"
  toSql (SqlStmt SqlPostInstall _ xs) = xs ++ "\n"
  toSql (SqlStmt _ _ xs) = termin $ xs
   where
    termin [] = undefined
    termin ys = ys ++ statementTermin
  (//) _ _ = undefined

sqlFromStmt :: SqlStatement -> String
sqlFromStmt (SqlStmt _ _ str) = str
sqlFromStmt SqlStmtEmpty = undefined

sqlPrinter :: [SqlStatement] -> String
sqlPrinter xs = join "" $ map toSql xs

toSqlString :: String -> String
toSqlString xs = "'" ++ replace "'" "''" xs ++ "'"

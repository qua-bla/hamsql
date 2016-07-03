-- This file is part of HamSql
--
-- Copyright 2014-2015 by it's authors.
-- Some rights reserved. See COPYING, AUTHORS.

{-# LANGUAGE OverloadedStrings #-}

module Database.HamSql.Internal.Stmt.Create where

import           Data.Maybe
import qualified Data.Text  as T

import Database.YamSql
import Database.HamSql.Internal.Sql
import Database.HamSql.Internal.Stmt.Commons
import Database.HamSql.Internal.Stmt.CreateSequence
import Database.HamSql.Internal.Stmt.CreateTable
import Database.HamSql.Internal.Option
import Database.HamSql.Setup
--import Database.HamSql

emptyName :: SqlName
emptyName = SqlName ""

sqlAddTransact :: [SqlStatement] -> [SqlStatement]
sqlAddTransact xs =
  [ SqlStmt SqlUnclassified emptyName "BEGIN TRANSACTION" ] ++
  xs ++
  [ SqlStmt SqlUnclassified emptyName "COMMIT" ]

-- create database

sqlCreateDatabase :: Bool -> SqlName -> [SqlStatement]
sqlCreateDatabase deleteDatabase name = [
        sqlDelete deleteDatabase,
        SqlStmt SqlCreateDatabase name $
          "CREATE DATABASE " <> toSql name,
        SqlStmt SqlCreateDatabase name
          "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC"
    ]
  where
    sqlDelete True = SqlStmt SqlDropDatabase name $
      "DROP DATABASE IF EXISTS" <-> toSql name
    sqlDelete False = SqlStmtEmpty

-- Setup

getSetupStatements :: OptCommon -> Setup -> [SqlStatement]
getSetupStatements opts s = debug opts "stmtInstallSetup" $
  [ getStmt $ setupPreCode s ] ++ schemaStatements ++ [ getStmt $ setupPostCode s ]
  where
    schemaStatements =
      concatMap (getSchemaStatements opts s) (setupSchemaData $ setupInternal s)
    getStmt (Just code) = SqlStmt SqlPreInstall emptyName code
    getStmt Nothing = SqlStmtEmpty

-- Schema

getSchemaStatements :: OptCommon -> Setup -> Schema -> [SqlStatement]
getSchemaStatements opts s m = debug opts "stmtCreateSchema" $
  [
    SqlStmt SqlCreateSchema (schemaName m) $ "CREATE SCHEMA IF NOT EXISTS" <-> toSql (schemaName m),
    postInst $ schemaExecPostInstall m,
    stmtCommentOn "schema" (schemaName m) (schemaDescription m)
  ] ++
  maybeMap (privUsage) (schemaPrivUsage m) ++
  maybeMap (privSelectAll) (schemaPrivSelectAll m) ++
  maybeMap (privInsertAll) (schemaPrivInsertAll m) ++
  maybeMap (privUpdateAll) (schemaPrivUpdateAll m) ++
  maybeMap (privDeleteAll) (schemaPrivDeleteAll m) ++
  maybeMap (privSequenceAll) (schemaPrivSequenceAll m) ++
  maybeMap (privExecuteAll) (schemaPrivExecuteAll m) ++
  concat (maybeMap (privAllAll) (schemaPrivAllAll m)) ++
  concat (maybeMap (getDomainStatements opts s m) (schemaDomains m)) ++
  concat (maybeMap (getTypeStatements opts s m) (schemaTypes m)) ++
  concat (maybeMap (getRoleStatements opts s) (schemaRoles m)) ++
  concat (maybeMap (getFunctionStatements opts s m) (schemaFunctions m)) ++
  concat (maybeMap (createTable opts s m) (schemaTables m)) ++
  concat (maybeMap (createSequence opts s m) (schemaSequences m))

  where
    postInst Nothing = SqlStmtEmpty
    postInst (Just xs) = SqlStmt SqlPostInstall emptyName xs

    priv :: Text -> SqlName -> SqlStatement
    priv p r = SqlStmt SqlPriv r $
      "GRANT " <> p <> " " <> toSql (schemaName m) <> " TO " <> prefixedRole s r

    privUsage = priv "USAGE ON SCHEMA"
    privSelectAll = priv "SELECT ON ALL TABLES IN SCHEMA"
    privInsertAll = priv "INSERT ON ALL TABLES IN SCHEMA"
    privUpdateAll = priv "UPDATE ON ALL TABLES IN SCHEMA"
    privDeleteAll = priv "DELETE ON ALL TABLES IN SCHEMA"
    privSequenceAll = priv "USAGE ON ALL SEQUENCES IN SCHEMA"
    privExecuteAll = priv "EXECUTE ON ALL FUNCTIONS IN SCHEMA"
    privAllAll d = map (\x -> x d)
      [
        privUsage,
        privSelectAll,
        privInsertAll,
        privUpdateAll,
        privDeleteAll,
        privSequenceAll,
        privExecuteAll
      ]

-- Function

getFunctionStatements :: OptCommon -> Setup -> Schema -> Function -> [SqlStatement]
getFunctionStatements _ setup m f =
    stmtCreateFunction:
    sqlSetOwner (functionOwner f):
    stmtComment:
    map sqlStmtGrantExecute (maybeList $ functionPrivExecute f)

    where
        name = (schemaName m) <.> functionName f

        sqlStmtGrantExecute u = SqlStmt SqlPriv name $ sqlGrantExecute u
        sqlGrantExecute u = "GRANT EXECUTE ON FUNCTION \n" <>
            sqlFunctionIdentifier <> "\nTO " <> prefixedRole setup u

        stmtCreateFunction = SqlStmtFunction SqlCreateFunction name
            (maybeMap variableType (functionParameters f))
            $
            "CREATE OR REPLACE FUNCTION " <> sqlFunctionIdentifierDef <>
            "\n" <>
            "RETURNS" <-> toSql (functionReturns f) <> sqlReturnsColumns (functionReturnsColumns f) <>
            "\nLANGUAGE " <> sqlLanguage (functionLanguage f) <>
            "\nSECURITY " <> sqlSecurity (functionSecurityDefiner f) <>
            "\nAS\n$BODY$\n" <>
                sqlBody <>
            "\n$BODY$\n"

        stmtComment = SqlStmt SqlComment (functionName f) $
          "COMMENT ON FUNCTION " <> sqlFunctionIdentifier <>
          " IS " <> toSqlString (functionDescription f)

        sqlSetOwner (Just o) = SqlStmt SqlPriv name $
            "ALTER FUNCTION " <> sqlFunctionIdentifier <>
            "OWNER TO " <> prefixedRole setup o
        sqlSetOwner Nothing = SqlStmtEmpty

        sqlFunctionIdentifierDef =
            toSql name
                <> "(\n" <>
                T.intercalate ",\n" (maybeMap sqlParameterDef (functionParameters f)) <>
                "\n)"

        sqlFunctionIdentifier =
            toSql name
                <> "(" <\>
                T.intercalate ",\n" (maybeMap sqlParameter (functionParameters f)) <\>
                ")"

        -- function parameter
        sqlParameter p =
            toSql(variableName p)
            <-> toSql(variableType p)

        sqlParameterDef p =
            toSql(variableName p)
            <-> toSql(variableType p)
            <-> sqlParamDefault (variableDefault p)
            where
            sqlParamDefault Nothing = ""
            sqlParamDefault (Just x) = "DEFAULT" <-> x

        -- If function returns a table, use service for field definition
        sqlReturnsColumns cs
         | toSql (functionReturns f) == "TABLE" =
            " (" <\>
            T.intercalate ",\n" (maybeMap sqlReturnsColumn cs) <>
            ") "
         | otherwise = ""

        sqlReturnsColumn c = toSql (parameterName c) <> " " <> toSql (parameterType c)

        -- If language not defined, use service for variable definitions
        sqlBody
            | isNothing (functionLanguage f) =
                "DECLARE" <\>
                sqlVariables (functionVariables f) <>
                "BEGIN" <\>
                body <\>
                "END;"
            | otherwise =
                body
            where
                body =
                    T.intercalate "\n" preludes <>
                    maybeText (functionBody f) <>
                    T.intercalate "\n" postludes

                preludes :: [Text]
                preludes = catMaybes$maybeMap functiontplBodyPrelude (functionTemplateData f)

                postludes :: [Text]
                postludes = catMaybes$maybeMap functiontplBodyPostlude (functionTemplateData f)


        -- Service for variable definitions
        sqlVariables Nothing = ""
        sqlVariables (Just vs) = T.concat (map sqlVariable vs)

        sqlVariable v =
            toSql (variableName v) <-> toSql(variableType v)
            <-> sqlVariableDefault (variableDefault v) <> ";\n"

        sqlVariableDefault Nothing = ""
        sqlVariableDefault (Just d) = ":=" <-> d

        -- SECURITY
        sqlSecurity (Just True) = "DEFINER"
        sqlSecurity _           = "INVOKER"

        -- LANGUAGE
        sqlLanguage Nothing     = "plpgsql"
        sqlLanguage (Just lang) = lang

-- Domains

getDomainStatements :: OptCommon -> Setup -> Schema -> Domain -> [SqlStatement]
getDomainStatements opt _ m d = debug opt "stmtCreateDomain" $

  stmtCreateDomain
  :sqlDefault (domainDefault d)
  :(maybeMap sqlCheck (domainChecks d))

  --stmtCommentOn "DOMAIN" fullName (domainDescription d)

    where
    fullName = (schemaName m) <.> domainName d

    stmtCreateDomain = SqlStmt SqlCreateDomain fullName $
      "CREATE DOMAIN" <-> toSql fullName <-> "AS" <-> toSql (domainType d)

    sqlCheck :: Check -> SqlStatement
    sqlCheck c = SqlStmt SqlCreateCheckConstr fullName $
      "ALTER DOMAIN" <-> toSql fullName
      <-> "ADD CONSTRAINT" <-> toSql (name (checkName c))
      <-> "CHECK (" <> checkCheck c <> ")"

    sqlDefault Nothing = SqlStmtEmpty
    sqlDefault (Just def) = SqlStmt SqlAddDefault fullName $
      "ALTER DOMAIN" <-> toSql fullName <-> "SET DEFAULT" <-> def

    name a = SqlName "DOMAIN_" // domainName d // SqlName "__" // a

-- Types

getTypeStatements :: OptCommon -> Setup -> Schema -> Type -> [SqlStatement]
getTypeStatements _ _ m t =
  SqlStmt SqlCreateType fullName (
    "CREATE TYPE" <-> toSql fullName <-> "AS (" <>
    T.intercalate ", " (map sqlElement (typeElements t)) <> ")"
  ):
  stmtCommentOn "TYPE" fullName (typeDescription t)
  :[]

  -- ALTER TYPE name ALTER ATTRIBUTE attribute_name [ SET DATA ] TYPE data_type

  where
    fullName = (schemaName m) <.> typeName t
    sqlElement e = toSql (typeelementName e) <-> toSql(typeelementType e)

-- Role

getRoleStatements :: OptCommon -> Setup -> Role -> [SqlStatement]
getRoleStatements _ setup r =
    SqlStmt SqlCreateRole (roleName r) sqlCreateRole:
    (stmtCommentOn "ROLE" (setupRolePrefix' setup // roleName r) (roleDescription r)):
    maybeMap sqlRoleMembership (roleMemberIn r)

    where
        sqlCreateRole =
          "CREATE ROLE" <-> prefix (roleName r)
          <-> sqlLogin (roleLogin r)
          <-> sqlPassword (rolePassword r)

        sqlRoleMembership group =
            SqlStmt SqlRoleMembership (roleName r) $
            "GRANT" <-> prefix group <-> "TO" <-> prefix (roleName r);

        sqlLogin (Just True) = "LOGIN"
        sqlLogin _           = "NOLOGIN"

        sqlPassword Nothing = ""
        sqlPassword (Just p) = "ENCRYPTED PASSWORD '" <> p <> "' "

        prefix role = prefixedRole setup role


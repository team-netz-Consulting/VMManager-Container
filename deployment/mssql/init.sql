SET NOCOUNT ON;

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    DECLARE @createDatabase nvarchar(max) = N'CREATE DATABASE ' + QUOTENAME(N'$(DatabaseName)');
    EXEC sys.sp_executesql @createDatabase;
END;
GO

IF SUSER_ID(N'$(AppUser)') IS NULL
BEGIN
    DECLARE @createLogin nvarchar(max) =
        N'CREATE LOGIN ' + QUOTENAME(N'$(AppUser)') +
        N' WITH PASSWORD = N''' + REPLACE(N'$(AppPassword)', N'''', N'''''') +
        N''', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF';
    EXEC sys.sp_executesql @createLogin;
END;
GO

USE [$(DatabaseName)];
GO

IF USER_ID(N'$(AppUser)') IS NULL
BEGIN
    DECLARE @createUser nvarchar(max) =
        N'CREATE USER ' + QUOTENAME(N'$(AppUser)') + N' FOR LOGIN ' + QUOTENAME(N'$(AppUser)');
    EXEC sys.sp_executesql @createUser;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members membership
    INNER JOIN sys.database_principals role ON role.principal_id = membership.role_principal_id
    INNER JOIN sys.database_principals member ON member.principal_id = membership.member_principal_id
    WHERE role.name = N'db_owner' AND member.name = N'$(AppUser)')
BEGIN
    DECLARE @addRoleMember nvarchar(max) =
        N'ALTER ROLE [db_owner] ADD MEMBER ' + QUOTENAME(N'$(AppUser)');
    EXEC sys.sp_executesql @addRoleMember;
END;
GO

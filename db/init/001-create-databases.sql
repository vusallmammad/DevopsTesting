SELECT 'CREATE DATABASE security'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'security')\gexec

SELECT 'CREATE DATABASE profile'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'profile')\gexec

SELECT 'CREATE DATABASE game'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'game')\gexec

SELECT 'CREATE DATABASE store'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'store')\gexec

SELECT 'CREATE DATABASE teams'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'teams')\gexec

SELECT 'CREATE DATABASE matchup'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'matchup')\gexec

SELECT 'CREATE DATABASE tournaments'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'tournaments')\gexec

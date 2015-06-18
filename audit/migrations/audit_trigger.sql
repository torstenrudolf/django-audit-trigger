-- modified to use jsonb fields instead hstore and store app specific parameters, like user_id, user_ip_address
-- because I do not know the order of the columns I didn't know how to use the row() like in the original
-- but declare the variables beforehand

-- the jsonb changes come form the excellent django-postgres project from matthew schinckel: bitbucket.org/schinckel/django-postgres


-- An audit history is important on most tables. Provide an audit trigger that logs to
-- a dedicated audit table for the major relations.
--
-- This file should be generic and not depend on application roles or structures,
-- as it's being listed here:
--
--    https://wiki.postgresql.org/wiki/Audit_trigger_91plus
--
-- This trigger was originally based on
--   http://wiki.postgresql.org/wiki/Audit_trigger
-- but has been completely rewritten.
--
-- Should really be converted into a relocatable EXTENSION, with control and upgrade files.

----CREATE EXTENSION IF NOT EXISTS hstore;
----
---- CREATE SCHEMA audit;
---- REVOKE ALL ON SCHEMA audit FROM public;
----
---- COMMENT ON SCHEMA audit IS 'Out-of-table audit/history logging tables and trigger functions';

--
-- Audited data. Lots of information is available, it's just a matter of how much
-- you really want to record. See:
--
--   http://www.postgresql.org/docs/9.1/static/functions-info.html
--
-- Remember, every column you add takes up more audit table space and slows audit
-- inserts.
--
-- Every index you add has a big impact too, so avoid adding indexes to the
-- audit table unless you REALLY need them. The hstore GIST indexes are
-- particularly expensive.
--
-- It is sometimes worth copying the audit table, or a coarse subset of it that
-- you're interested in, into a temporary table where you CREATE any useful
-- indexes and do your analysis.
--

CREATE SCHEMA audit;
COMMENT ON SCHEMA audit IS 'Out-of-table audit/history trigger functions';

CREATE OR REPLACE FUNCTION "jsonb_subtract"(
  "json" jsonb,
  "remove" TEXT
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  STRICT
AS $function$

SELECT
  CASE WHEN "json" ? "remove"
    THEN COALESCE(
      (SELECT json_object_agg("key", "value") FROM jsonb_each("json") WHERE "key" <> "remove"),
      '{}'
    )::jsonb
    ELSE "json"
END

$function$;


CREATE OR REPLACE FUNCTION "jsonb_subtract"(
  "json" jsonb,
  "keys" TEXT[]
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  STRICT
AS $function$


SELECT CASE WHEN "json" ?| "keys" THEN COALESCE(
  (SELECT json_object_agg("key", "value") FROM jsonb_each("json") WHERE "key" <> ALL("keys")),
  '{}'::json
)::jsonb
ELSE "json"
END

$function$;

CREATE OR REPLACE FUNCTION "jsonb_subtract_obj"(
  "json" jsonb,
  "remove" jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  STRICT
AS $function$

SELECT COALESCE(json_object_agg("key", "value"), '{}'::json)::jsonb
FROM (
  SELECT key, value FROM jsonb_each("json")
  EXCEPT
  SELECT key, value FROM jsonb_each("remove")
) x

$function$;


CREATE OR REPLACE FUNCTION "jsonb_subtract"(
  "json" jsonb,
  "remove" json
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  STRICT
AS $function$

SELECT
  CASE
    WHEN json_typeof("remove") = 'array' THEN
      jsonb_subtract("json", json_array_elements_text("remove"))
    ELSE
      jsonb_subtract_obj("json", "remove"::jsonb)
  END

$function$;


CREATE OR REPLACE FUNCTION "jsonb_subtract"(
  "json" jsonb,
  "remove" jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  STRICT
AS $function$

SELECT
  CASE
    WHEN jsonb_typeof("remove") = 'array' THEN
      jsonb_subtract("json", jsonb_array_elements_text("remove"))
    ELSE
      jsonb_subtract_obj("json", "remove")
  END

$function$;


CREATE OR REPLACE FUNCTION audit.if_modified_func()
  RETURNS TRIGGER AS $body$
DECLARE
  row_data            JSONB;
  changed_fields      JSONB;
  excluded_cols       TEXT [] = ARRAY [] :: TEXT [];

  client_query        TEXT;
  statement_only      BOOLEAN;
  -- trigger is either a row-level or statement-level trigger

  app_name            TEXT;
  app_user_id         INTEGER;
  app_user_ip_address INET;

BEGIN
  IF TG_WHEN <> 'AFTER'
  THEN
    RAISE EXCEPTION 'audit.if_modified_func() may only run as an AFTER trigger';
  END IF;

  -- Inject the data from the app settings if they exist.
  -- We need to do this in a transaction, as there doesn't
  -- seem to be any way to test existence.
  BEGIN
    SELECT INTO app_name CURRENT_SETTING('app_name');
    SELECT INTO app_user_id CURRENT_SETTING('app_user_id');
    SELECT INTO app_user_ip_address CURRENT_SETTING('app_user_ip_address');
    EXCEPTION WHEN OTHERS THEN
  END;

  IF TG_ARGV [0] :: BOOLEAN IS DISTINCT FROM 'f' :: BOOLEAN
  THEN
    client_query = current_query();
  ELSE
    client_query = NULL;
  END IF;

  IF TG_ARGV [1] IS NOT NULL
  THEN
    excluded_cols = TG_ARGV [1] :: TEXT [];
  END IF;

  IF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW')
  THEN
    -- Convert our table to a json structure.
    row_data = to_json(OLD.*) :: JSONB;
    -- Remove any columns we want to exclude, and then any
    -- columns that still have the same value as before the update.
    changed_fields = jsonb_subtract(jsonb_subtract(to_json(NEW.*) :: JSONB, row_data), excluded_cols);

    IF changed_fields = '{}' :: JSONB
    THEN
      -- All changed fields are ignored. Skip this update.
      RETURN NULL;
    END IF;
  ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW')
    THEN
      row_data = jsonb_subtract(to_json(OLD.*) :: JSONB, excluded_cols);
  ELSIF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW')
    THEN
      row_data = jsonb_subtract(to_json(NEW.*) :: JSONB, excluded_cols);
  ELSIF (TG_LEVEL = 'STATEMENT' AND TG_OP IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
    THEN
      statement_only = 't';
  ELSE
    RAISE EXCEPTION '[audit.if_modified_func] - Trigger func added as trigger for unhandled case: %, %', TG_OP, TG_LEVEL;
    RETURN NULL;
  END IF;

  INSERT INTO public.audit_auditlog (
    "db_schema_name",
    "db_table_name",
    "db_relid",
    "db_session_user_name",
    "db_current_timestamp", -- start of transaction
    "db_statement_timestamp", -- start of statement
    "db_clock_timestamp", -- now
    "db_transaction_id",

    "db_client_addr",
    "db_client_port",
    "db_client_query",

    "db_action",
    "row_data",
    "changed_fields",
    "statement_only",

    "app_name",
    "app_user_id",
    "app_user_ip_address"

  ) VALUES (
    TG_TABLE_SCHEMA :: TEXT, -- schema_name
    TG_TABLE_NAME :: TEXT, -- table_name
    TG_RELID, -- relation OID for much quicker searches
    session_user :: TEXT, -- session_user_name
    current_timestamp, -- action_tstamp_tx
    statement_timestamp(), -- action_tstamp_stm
    clock_timestamp(), -- action_tstamp_clk
    txid_current(), -- transaction ID

    inet_client_addr(), -- client_addr
    inet_client_port(), -- client_port
    client_query, -- top-level query or queries (if multistatement) from client

    TG_OP, -- action
    row_data, -- row_data
    changed_fields, -- changed_fields
    'f', -- statement_only

    app_name,
    app_user_id,
    app_user_ip_address
  );


  RETURN NULL;
END;
$body$
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public;


COMMENT ON FUNCTION audit.if_modified_func() IS $body$
Track changes to a table at the statement and/or row level.

Optional parameters to trigger in CREATE TRIGGER call:

param 0: boolean, whether to log the query text. Default 't'.

param 1: text[], columns to ignore in updates. Default [].

         Updates to ignored cols are omitted from changed_fields.

         Updates with only ignored cols changed are not inserted
         into the audit log.

         Almost all the processing work is still done for updates
         that ignored. If you need to save the load, you need to use
         WHEN clause on the trigger instead.

         No warning or error is issued if ignored_cols contains columns
         that do not exist in the target table. This lets you specify
         a standard set of ignored columns.

There is no parameter to disable logging of values. Add this trigger as
a 'FOR EACH STATEMENT' rather than 'FOR EACH ROW' trigger if you do not
want to log row values.

Note that the user name logged is the login role for the session. The audit trigger
cannot obtain the active role because it is reset by the SECURITY DEFINER invocation
of the audit trigger its self.
$body$;





-- convenient functions to create and drop table auditing triggers


CREATE OR REPLACE FUNCTION audit.audit_table(target_table REGCLASS, audit_rows BOOLEAN, audit_query_text BOOLEAN, ignored_cols TEXT [])
  RETURNS VOID AS $body$
DECLARE
  stm_targets        TEXT = 'INSERT OR UPDATE OR DELETE OR TRUNCATE';
  _q_txt             TEXT;
  _ignored_cols_snip TEXT = '';
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_row ON ' || target_table;
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_stm ON ' || target_table;

  IF audit_rows
  THEN
    IF array_length(ignored_cols, 1) > 0
    THEN
      _ignored_cols_snip = ', ' || quote_literal(ignored_cols);
    END IF;
    _q_txt = 'CREATE TRIGGER audit_trigger_row AFTER INSERT OR UPDATE OR DELETE ON ' ||
             target_table ||
             ' FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func(' ||
             quote_literal(audit_query_text) || _ignored_cols_snip || ');';
    RAISE NOTICE '%', _q_txt;
    EXECUTE _q_txt;
    stm_targets = 'TRUNCATE';
  ELSE
  END IF;

  _q_txt = 'CREATE TRIGGER audit_trigger_stm AFTER ' || stm_targets || ' ON ' ||
           target_table ||
           ' FOR EACH STATEMENT EXECUTE PROCEDURE audit.if_modified_func(' ||
           quote_literal(audit_query_text) || ');';
  RAISE NOTICE '%', _q_txt;
  EXECUTE _q_txt;

END;
$body$
LANGUAGE 'plpgsql';

COMMENT ON FUNCTION audit.audit_table(REGCLASS, BOOLEAN, BOOLEAN, TEXT []) IS $body$
Add auditing support to a table.

Arguments:
   target_table:     Table name, schema qualified if not on search_path
   audit_rows:       Record each row change, or only audit at a statement level
   audit_query_text: Record the text of the client query that triggered the audit event?
   ignored_cols:     Columns to exclude from update diffs, ignore updates that change only ignored cols.
$body$;

-- Pg doesn't allow variadic calls with 0 params, so provide a wrapper
CREATE OR REPLACE FUNCTION audit.audit_table(target_table REGCLASS, audit_rows BOOLEAN, audit_query_text BOOLEAN)
  RETURNS VOID AS $body$
SELECT audit.audit_table($1, $2, $3, ARRAY [] :: TEXT []);
$body$ LANGUAGE SQL;

-- And provide a convenience call wrapper for the simplest case
-- of row-level logging with no excluded cols and query logging enabled.
--
CREATE OR REPLACE FUNCTION audit.audit_table(target_table REGCLASS)
  RETURNS VOID AS $$
SELECT audit.audit_table($1, BOOLEAN 't', BOOLEAN 't');
$$ LANGUAGE 'sql';

COMMENT ON FUNCTION audit.audit_table(REGCLASS) IS $body$
Add auditing support to the given table. Row-level changes will be logged with full client query text. No cols are ignored.
$body$;


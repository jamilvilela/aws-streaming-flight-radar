import sys
import os
import traceback

def log(msg):
    print(f"DEBUG_FLINK: {msg}", flush=True)

log("Starting Python process...")

try:
    from pyflink.table import EnvironmentSettings, TableEnvironment
    log("PyFlink imports successful.")
except Exception as e:
    log(f"FATAL ERROR DURING IMPORTS: {str(e)}")
    traceback.print_exc()
    sys.exit(1)

def get_java_exception_cause(e):
    try:
        if hasattr(e, 'java_exception'):
            cause = e.java_exception.getCause()
            while cause is not None and cause.getCause() is not None:
                cause = cause.getCause()
            return cause.getMessage() if cause else e.java_exception.getMessage()
    except:
        pass
    return str(e)

def main():
    log("Entering main() function...")
    
    try:
        env_settings = EnvironmentSettings.in_streaming_mode()
        table_env = TableEnvironment.create(env_settings)
        table_env.get_config().set("restart-strategy.type", "none")
        
        base_dir = os.path.dirname(os.path.abspath(__file__))
        jar_path = os.path.join(base_dir, "lib", "flink-sql-connector-aws-kinesis-streams-5.0.0-1.20.jar")
        if os.path.exists(jar_path):
            log(f"Found JAR: {jar_path}")
            table_env.get_config().get_configuration().set_string("pipeline.jars", f"file://{jar_path}")
        else:
            log(f"WARNING: JAR not found at {jar_path}")
        
        sql_files = [
            ("source", os.path.join(base_dir, "01_source.sql")),
            ("view", os.path.join(base_dir, "02_enriched_view.sql")),
            ("sinks", os.path.join(base_dir, "03_sinks_s3.sql"))
        ]

        # Get environment variables for SQL substitution
        kinesis_stream_arn = os.environ.get("KINESIS_STREAM_ARN", "")
        aws_region = os.environ.get("AWS_REGION", "us-east-1")
        
        if not kinesis_stream_arn:
            log("ERROR: KINESIS_STREAM_ARN environment variable not set")
            sys.exit(1)

        statement_set = table_env.create_statement_set()
        has_inserts = False

        for name, file_path in sql_files:
            log(f"Reading SQL file: {name}")
            with open(file_path, "r", encoding="utf-8") as f:
                sql_content = f.read()
            
            # Perform variable substitution
            sql_content = sql_content.replace("${KINESIS_STREAM_ARN}", kinesis_stream_arn)
            sql_content = sql_content.replace("${AWS_REGION}", aws_region)
            
            raw_statements = sql_content.split(';')
            for raw_stmt in raw_statements:
                lines = raw_stmt.split('\n')
                clean_lines = [line for line in lines if not line.strip().startswith('--')]
                clean_statement = '\n'.join(clean_lines).strip()
                
                if not clean_statement:
                    continue

                if clean_statement.upper().startswith("INSERT"):
                    log(f"Adding INSERT to StatementSet from {name}")
                    statement_set.add_insert_sql(clean_statement)
                    has_inserts = True
                else:
                    log(f"Executing DDL: {clean_statement[:50]}...")
                    table_env.execute_sql(clean_statement)
        
        if has_inserts:
            log("Submitting Flink Job...")
            table_result = statement_set.execute()
            log(f"Job submitted. ID: {table_result.get_job_client().get_job_id() if table_result.get_job_client() else 'N/A'}")
        else:
            log("No INSERT statements found.")
                
    except Exception as e:
        log(f"FATAL ERROR DURING EXECUTION: {get_java_exception_cause(e)}")
        traceback.print_exc()
        sys.exit(1)

    log("Python script finished successfully.")

if __name__ == '__main__':
    main()

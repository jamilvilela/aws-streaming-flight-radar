import os
import sys
from pyflink.table import EnvironmentSettings, TableEnvironment

def main():
    # Inicializa o Table Environment em modo Streaming
    env_settings = EnvironmentSettings.in_streaming_mode()
    table_env = TableEnvironment.create(env_settings)

    # Lê as propriedades de runtime injetadas pela AWS (para pegar a região)
    # Em um app mais robusto leríamos o application_properties.json,
    # mas o SQL tem a região fixada (us-east-1) então podemos apenas rodar.
    
    # Ordem de execução: Source -> View -> Sinks
    sql_files = [
        "01_source.sql",
        "02_enriched_view.sql",
        "03_sinks_kinesis.sql"
    ]

    print("[INFO] Iniciando PyFlink SQL Wrapper...")
    
    for file_path in sql_files:
        print(f"[INFO] Lendo e executando: {file_path}")
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                sql_content = f.read()
            
            # O SQL pode ter múltiplos statements separados por ponto e vírgula.
            # O PyFlink 1.15+ suporta rodar SQL statements diretamente,
            # mas table_env.execute_sql suporta um statement por vez.
            statements = [s.strip() for s in sql_content.split(';') if s.strip()]
            for statement in statements:
                # Evita executar linhas de comentário vazias ou statements vazios
                if statement and not statement.startswith('--'):
                    # Retira blocos de comentários puramente antes do comando
                    lines = [line for line in statement.split('\n') if not line.strip().startswith('--')]
                    clean_statement = '\n'.join(lines).strip()
                    if clean_statement:
                        print(f"[INFO] Executando statement:\n{clean_statement[:100]}...")
                        table_env.execute_sql(clean_statement)
            
        except Exception as e:
            print(f"[ERROR] Falha ao processar {file_path}: {str(e)}")
            sys.exit(1)

    print("[INFO] Todos os statements SQL foram carregados. Aguardando streaming...")

if __name__ == '__main__':
    main()

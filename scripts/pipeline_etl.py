import os
import urllib
import pandas as pd
from sqlalchemy import create_engine

def ingestar_datos_raw():
    print("🚀 Iniciando la fase de Ingesta de Datos en SQL Server (Zona RAW)...")
    
    # 1. Rutas de los archivos de origen
    base_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(base_dir)
    
    csv_files = {
        "raw_customers": os.path.join(project_dir, "datasets", "customers.csv"),
        "raw_products": os.path.join(project_dir, "datasets", "products.csv"),
        "raw_orders": os.path.join(project_dir, "datasets", "orders.csv")
    }
    
    # 2. CONFIGURACIÓN DE CONEXIÓN A SQL SERVER
    SERVER = 'JOAQUINCR\SQLEXPRESS'  
    DATABASE = 'master'   
    
    connection_string = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
    params = urllib.parse.quote_plus(connection_string)
    engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")
    
    try:
        # 3. Leer cada archivo CSV e ingresarlo a SQL Server
        for table_name, file_path in csv_files.items():
            if not os.path.exists(file_path):
                raise FileNotFoundError(f"⚠️ No se encontró el archivo en {file_path}.")
            
            print(f"📖 Leyendo {file_path} con protección de encoding...")
            
            # Intentamos leer con 'utf-8-sig' (ignora firmas BOM de Excel) y si falla, usamos 'latin-1'
            try:
                df_raw = pd.read_csv(file_path, dtype=str, encoding='utf-8-sig', sep=None, engine='python')
            except UnicodeDecodeError:
                df_raw = pd.read_csv(file_path, dtype=str, encoding='latin-1', sep=None, engine='python')
            
            # Cargar a SQL Server
            df_raw.to_sql(table_name, con=engine, if_exists="replace", index=False)
            print(f"✅ Tabla '{table_name}' cargada en SQL Server con {len(df_raw)} filas.")
            
        print("\n🏆 ¡Fase de Ingesta RAW en SQL Server completada con éxito!")
        
    except Exception as e:
        print(f"❌ Ocurrió un error durante la ingesta: {str(e)}")

if __name__ == "__main__":
    ingestar_datos_raw()
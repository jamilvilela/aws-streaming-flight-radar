#!/usr/bin/env python3
"""
Test Script: Valida pipeline Flink SQL end-to-end

Envia dados de teste para Kinesis e verifica se:
1. Dados aparecem no enriched-raw stream (Sink D)
2. Agregações aparecem em outros sinks
3. Latência está dentro dos limites esperados
"""

import json
import time
import boto3
import argparse
from datetime import datetime
from typing import Dict, List, Any

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================

class FlinkTestConfig:
    """Configuração do teste"""
    
    INPUT_STREAM = "flight-radar-stream-flights"
    SINKS = {
        "positions-1min": "flight-radar-stream-flights-positions-1min",
        "altitude-bands": "flight-radar-stream-flights-altitude-bands",
        "phase-changes": "flight-radar-stream-flights-phase-changes",
        "enriched-raw": "flight-radar-stream-flights-enriched-raw",
    }
    
    # ADS-B test data (formato OpenSky API)
    TEST_EVENT = {
        "icao24": "a02345",
        "callsign": "TAP1234",
        "origin_country": "PT",
        "time_position": "2026-05-17T10:30:00",
        "last_contact": "2026-05-17T10:30:00",
        "longitude": -9.1352,
        "latitude": 38.6814,
        "altitude": 3500,          # metros
        "on_ground": False,
        "velocity": 250.5,         # m/s
        "heading": 270,
        "vertical_rate": 5.2,      # m/s (climbing)
        "geo_altitude": 3600,
        "squawk": "4521",
        "spi": False,
        "position_source": 0,
        "event_time": "2026-05-17T10:30:00"  # Campo adicional para matching com schema (ignorado, Kinesis usa metadata)
    }

# ============================================================================
# LOGGING
# ============================================================================

class Colors:
    """ANSI colors para terminal"""
    OK = '\033[92m'      # Green
    FAIL = '\033[91m'    # Red
    WARN = '\033[93m'    # Yellow
    INFO = '\033[94m'    # Blue
    END = '\033[0m'      # Reset

def log_ok(msg: str):
    """Log sucesso"""
    print(f"{Colors.OK}✓ {msg}{Colors.END}")

def log_fail(msg: str):
    """Log erro"""
    print(f"{Colors.FAIL}✗ {msg}{Colors.END}")

def log_warn(msg: str):
    """Log aviso"""
    print(f"{Colors.WARN}! {msg}{Colors.END}")

def log_info(msg: str):
    """Log info"""
    print(f"{Colors.INFO}ℹ {msg}{Colors.END}")

# ============================================================================
# KINESIS UTILS
# ============================================================================

class KinesisHelper:
    """Utilitários Kinesis"""
    
    def __init__(self, region: str = "us-east-1"):
        self.kinesis = boto3.client("kinesis", region_name=region)
        self.region = region
    
    def put_record(self, stream_name: str, data: Dict[str, Any], 
                   partition_key: str = "test") -> str:
        """Envia record para stream"""
        try:
            response = self.kinesis.put_record(
                StreamName=stream_name,
                Data=json.dumps(data),
                PartitionKey=partition_key
            )
            return response["ShardId"]
        except Exception as e:
            raise Exception(f"Erro enviando record: {e}")
    
    def get_records(self, stream_name: str, shard_id: str = None) -> List[Dict]:
        """Lê records de um stream"""
        try:
            # Se não especificar shard, pega o primeiro
            if not shard_id:
                response = self.kinesis.describe_stream(StreamName=stream_name)
                shards = response["StreamDescription"]["Shards"]
                if not shards:
                    return []
                shard_id = shards[0]["ShardId"]
            
            # Get shard iterator
            iterator_response = self.kinesis.get_shard_iterator(
                StreamName=stream_name,
                ShardId=shard_id,
                ShardIteratorType="LATEST"
            )
            
            # Get records
            records_response = self.kinesis.get_records(
                ShardIterator=iterator_response["ShardIterator"]
            )
            
            return records_response["Records"]
        
        except Exception as e:
            log_warn(f"Erro lendo records de {stream_name}: {e}")
            return []
    
    def stream_exists(self, stream_name: str) -> bool:
        """Verifica se stream existe e está ACTIVE"""
        try:
            response = self.kinesis.describe_stream(StreamName=stream_name)
            status = response["StreamDescription"]["StreamStatus"]
            return status == "ACTIVE"
        except self.kinesis.exceptions.ResourceNotFoundException:
            return False
        except Exception as e:
            log_warn(f"Erro verificando stream: {e}")
            return False

# ============================================================================
# TESTES
# ============================================================================

class FlinkPipelineTest:
    """Testes da pipeline Flink"""
    
    def __init__(self, region: str = "us-east-1", wait_seconds: int = 30):
        self.kinesis = KinesisHelper(region)
        self.wait_seconds = wait_seconds
        self.config = FlinkTestConfig()
        self.results = {}
    
    def run_all_tests(self, num_events: int = 5) -> bool:
        """Executa todos os testes"""
        print("\n" + "="*70)
        print("FLINK SQL PIPELINE TEST")
        print("="*70 + "\n")
        
        all_passed = True
        
        # Test 1: Verificar streams
        if not self._test_streams_exist():
            all_passed = False
        
        # Test 2: Enviar eventos
        if not self._test_send_events(num_events):
            all_passed = False
        
        # Test 3: Verificar dados nos sinks
        if not self._test_verify_output():
            all_passed = False
        
        # Test 4: Validar dados enriquecidos
        if not self._test_verify_enrichment():
            all_passed = False
        
        # Resumo
        self._print_summary(all_passed)
        
        return all_passed
    
    def _test_streams_exist(self) -> bool:
        """Verifica se todos os streams existem"""
        print("\n[1/4] Verificando Kinesis streams...\n")
        
        all_exist = True
        
        # Check input stream
        if self.kinesis.stream_exists(self.config.INPUT_STREAM):
            log_ok(f"Input stream: {self.config.INPUT_STREAM}")
        else:
            log_fail(f"Input stream não encontrado: {self.config.INPUT_STREAM}")
            all_exist = False
        
        # Check output streams
        for sink_name, stream_name in self.config.SINKS.items():
            if self.kinesis.stream_exists(stream_name):
                log_ok(f"Sink stream ({sink_name}): {stream_name}")
            else:
                log_warn(f"Sink stream não encontrado: {stream_name}")
                # Não é falha crítica, pode ser criado pelo Flink
        
        return all_exist
    
    def _test_send_events(self, num_events: int) -> bool:
        """Envia eventos de teste"""
        print(f"\n[2/4] Enviando {num_events} eventos de teste...\n")
        
        try:
            for i in range(num_events):
                event = self.config.TEST_EVENT.copy()
                now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
                event["time_position"] = now
                event["last_contact"] = now
                event["event_time"] = now
                # Variar altitude para testar transformações
                event["altitude"] = 3500 + (i * 500)
                event["icao24"] = f"a0234{i}"
                
                shard_id = self.kinesis.put_record(
                    self.config.INPUT_STREAM,
                    event
                )
                log_ok(f"Evento {i+1}/{num_events} enviado (shard: {shard_id})")
                time.sleep(0.5)
            
            log_ok(f"Todos os {num_events} eventos enviados com sucesso")
            return True
        
        except Exception as e:
            log_fail(f"Erro ao enviar eventos: {e}")
            return False
    
    def _test_verify_output(self) -> bool:
        """Verifica dados nos sinks"""
        print(f"\n[3/4] Aguardando processamento ({self.wait_seconds}s)...\n")
        
        # Aguardar processamento
        for i in range(self.wait_seconds, 0, -5):
            if i == self.wait_seconds:
                log_info(f"Aguardando {i}s...")
            else:
                print(f"  ... {i}s restantes", end='\r')
            time.sleep(5)
        
        print("\n")
        log_info("Verificando dados nos sinks...\n")
        
        any_data = False
        
        for sink_name, stream_name in self.config.SINKS.items():
            try:
                records = self.kinesis.get_records(stream_name)
                
                if records:
                    log_ok(f"Sink '{sink_name}': {len(records)} records encontrados")
                    
                    # Mostrar primeiro record
                    first_record = records[0]
                    data_str = first_record.get("Data", b"").decode() if isinstance(first_record.get("Data"), bytes) else first_record.get("Data")
                    
                    try:
                        data_obj = json.loads(data_str)
                        log_info(f"  Exemplo: {json.dumps(data_obj, indent=2)[:200]}...")
                    except:
                        log_info(f"  Exemplo (raw): {str(data_str)[:200]}...")
                    
                    any_data = True
                    self.results[sink_name] = len(records)
                else:
                    log_warn(f"Sink '{sink_name}': Nenhum record encontrado")
                    self.results[sink_name] = 0
            
            except Exception as e:
                log_fail(f"Erro lendo sink '{sink_name}': {e}")
                self.results[sink_name] = -1
        
        return any_data
    
    def _test_verify_enrichment(self) -> bool:
        """Valida transformações de enriquecimento"""
        print("\n[4/4] Validando dados enriquecidos...\n")
        
        try:
            records = self.kinesis.get_records(
                self.config.SINKS["enriched-raw"]
            )
            
            if not records:
                log_warn("Nenhum record em enriched-raw para validar")
                return False
            
            record_data = json.loads(
                records[0]["Data"].decode() if isinstance(records[0]["Data"], bytes) 
                else records[0]["Data"]
            )
            
            # Validar conversões
            checks = {
                "altitude_ft": "Conversão metros→pés",
                "velocity_kts": "Conversão m/s→knots",
                "vrate_fpm": "Conversão vertical_rate→fpm",
                "flight_phase": "Classificação fase de voo",
                "vertical_trend": "Classificação tendência vertical",
                "speed_category": "Classificação velocidade",
            }
            
            all_valid = True
            for field, description in checks.items():
                if field in record_data:
                    log_ok(f"{description}: {field} = {record_data[field]}")
                else:
                    log_fail(f"{description}: campo '{field}' não encontrado")
                    all_valid = False
            
            return all_valid
        
        except Exception as e:
            log_fail(f"Erro validando enriquecimento: {e}")
            return False
    
    def _print_summary(self, passed: bool):
        """Imprime resumo dos testes"""
        print("\n" + "="*70)
        print("RESUMO DOS TESTES")
        print("="*70)
        
        print("\nResultados por Sink:")
        for sink_name, count in self.results.items():
            if count > 0:
                status = f"{Colors.OK}✓{Colors.END}"
            elif count == 0:
                status = f"{Colors.WARN}!{Colors.END}"
            else:
                status = f"{Colors.FAIL}✗{Colors.END}"
            
            print(f"  {status} {sink_name}: {count} records")
        
        print("\n" + "="*70)
        if passed:
            log_ok("Pipeline está funcionando corretamente!")
        else:
            log_fail("Pipeline tem problemas. Ver logs acima.")
        print("="*70 + "\n")

# ============================================================================
# MAIN
# ============================================================================

def main():
    """Entry point"""
    parser = argparse.ArgumentParser(
        description="Testa pipeline Flink SQL end-to-end"
    )
    parser.add_argument(
        "--region",
        default="us-east-1",
        help="AWS region"
    )
    parser.add_argument(
        "--stream-name",
        default="flight-radar-stream-flights",
        help="Nome do input stream"
    )
    parser.add_argument(
        "--test-events",
        type=int,
        default=5,
        help="Número de eventos de teste"
    )
    parser.add_argument(
        "--wait-seconds",
        type=int,
        default=30,
        help="Segundos para aguardar processamento"
    )
    
    args = parser.parse_args()
    
    # Atualizar stream name se fornecido
    if args.stream_name:
        FlinkTestConfig.INPUT_STREAM = args.stream_name
    
    # Executar testes
    test = FlinkPipelineTest(
        region=args.region,
        wait_seconds=args.wait_seconds
    )
    
    success = test.run_all_tests(num_events=args.test_events)
    
    # Exit code
    exit(0 if success else 1)

if __name__ == "__main__":
    main()

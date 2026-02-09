import os
import json
import logging
import boto3
import requests
from utils.models import StateVector
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
secrets_client = boto3.client("secretsmanager")
kinesis_client = boto3.client("kinesis")

# OpenSky OAuth2 + API endpoints
OPENSKY_TOKEN_URL = (
    "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
)
OPENSKY_STATES_URL = "https://opensky-network.org/api/states/all"



def _get_opensky_credentials_from_secret():
    """
    Lê client_id e client_secret do AWS Secrets Manager.

    Espera que o secret (apontado por OPENSKY_SECRET_ARN) tenha o formato:
    {
      "client_id": "xxxx",
      "client_secret": "yyyy"
    }
    """
    secret_arn = os.environ.get("OPENSKY_SECRET_ARN")
    if not secret_arn:
        logger.error("Missing OPENSKY_SECRET_ARN in environment variables")
        return None, None

    try:
        resp = secrets_client.get_secret_value(SecretId=secret_arn)
        secret_data = json.loads(resp["SecretString"])
        client_id = secret_data.get("client_id")
        client_secret = secret_data.get("client_secret")
        if not client_id or not client_secret:
            logger.error("Credentials is missing in secret")
            return None, None
        return client_id, client_secret
    except Exception as e:
        logger.error(f"Error retrieving OpenSky credentials from Secrets Manager: {e}")
        return None, None

def get_opensky_access_token():
    """
    Autentica na OpenSky via OAuth2 Client Credentials e retorna o access_token (Bearer).
    """
    client_id, client_secret = _get_opensky_credentials_from_secret()
    if not client_id or not client_secret:
        return None

    data = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }

    try:
        resp = requests.post(OPENSKY_TOKEN_URL, data=data, timeout=60)
        resp.raise_for_status()
        access_token = resp.json().get("access_token")
        if not access_token:
            logger.error("No access_token in OpenSky auth response")
            return None
        logger.info("Successfully obtained OpenSky access token")
        return access_token
    except requests.RequestException as e:
        logger.error(f"Error obtaining OpenSky access token: {e}")
        return None


def convert_states_response_to_json(states: list[StateVector]) -> dict:
    json_data = {
        "timestamp": datetime.now().isoformat(),
        "total_states": 0,
        "states": [],
    }
    for state in states:
        if state.origin_country != "Brazil":
            continue
        json_data["states"].append(state.to_dict())

    json_data["total_states"] = len(json_data["states"])
    return json_data

def send_state_to_kinesis(state_dict: dict) -> bool:
    """Envia um único registro para o Kinesis.

    Lê o nome do stream da variável de ambiente KINESIS_STREAM.
    Retorna True em caso de sucesso, False em caso de erro.
    """
    stream_name = os.environ.get("KINESIS_STREAM")
    if not stream_name:
        logger.error("KINESIS_STREAM environment variable not set")
        return False

    try:
        kinesis_client.put_record(
            StreamName=stream_name,
            Data=json.dumps(state_dict),
            PartitionKey=state_dict.get("icao24") or "unknown",
        )
        logger.info(
            f"State {state_dict.get('icao24', 'unknown')} sent to Kinesis successfully"
        )
        return True
    except Exception as e:
        logger.error(f"Error sending state to Kinesis: {e}")
        return False


def send_states_to_kinesis(json_resultado: dict) -> bool:
    """Envia todos os estados para o Kinesis.

    Retorna True se todos forem enviados com sucesso, False caso ocorra algum erro.
    """
    all_ok = True
    for state in json_resultado["states"]:
        ok = send_state_to_kinesis(state)
        if not ok:
            all_ok = False
    logger.info(
        f"Sent {len(json_resultado['states'])} states to Kinesis stream (check logs for failures)"
    )
    return all_ok


def get_opensky_states(access_token):
    """
    Chama o endpoint /api/states/all usando Bearer token e
    retorna uma lista de StateVector.
    """
    headers = {"Authorization": f"Bearer {access_token}"}

    try:
        resp = requests.get(OPENSKY_STATES_URL, headers=headers, timeout=15)
        resp.raise_for_status()
        body = resp.json()
    except requests.RequestException as e:
        logger.error(f"Error calling OpenSky states API: {e}")
        return []

    raw_states = body.get("states", []) or []
    states: list[StateVector] = []

    for row in raw_states:
        try:
            state = StateVector.from_api_response(row)
            states.append(state)
        except Exception as e:
            logger.warning(f"Failed to parse state vector: {e}")

    logger.info(f"Retrieved {len(states)} state vectors from OpenSky API")
    return states



def lambda_handler(event, context):
    """
    Main Lambda handler that orchestrates the flight data ingestion pipeline.
    """
    # DEBUG: Verificar DNS
    import socket
    try:
        logger.info("Testing DNS resolution...")
        ip = socket.gethostbyname('auth.opensky-network.org')
        logger.info(f"✅ DNS resolved: auth.opensky-network.org → {ip}")
    except socket.gaierror as e:
        logger.error(f"❌ DNS resolution failed: {e}")
        return {
            "statusCode": 503,
            "body": json.dumps({"error": f"DNS error: {str(e)}"})
        }
    
    # DEBUG: Verificar conectividade TCP
    try:
        logger.info("Testing TCP connectivity to port 443...")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(30)
        result = sock.connect_ex((ip, 443))
        sock.close()
        
        if result == 0:
            logger.info("✅ Port 443 is open")
        else:
            logger.error(f"❌ Port 443 is blocked (errno: {result})")
    except Exception as e:
        logger.error(f"❌ Error testing TCP: {e}")
        
    try:
        # 1) Autenticar na OpenSky (OAuth2 Client Credentials)
        logger.info("Getting OpenSky access token...")
        access_token = get_opensky_access_token()
        if not access_token:
            return {
                "statusCode": 500,
                "body": json.dumps("Failed to obtain OpenSky access token"),
            }

        # 2) Buscar estados de voos
        logger.info("Starting to fetch states from OpenSky API...")
        states = get_opensky_states(access_token)
        if not states:
            logger.warning("No states retrieved from OpenSky API")
            return {
                "statusCode": 500,
                "body": json.dumps("Failed to retrieve states from OpenSky API"),
            }

        # 3) Converter para JSON
        logger.info("Converting states to JSON format...")
        json_resultado = convert_states_response_to_json(states)

        # 4) Enviar para Kinesis
        logger.info(
            f"Sending {len(json_resultado['states'])} states to Kinesis stream..."
        )
        ok = send_states_to_kinesis(json_resultado)
        if not ok:
            # erro pode ser KINESIS_STREAM ausente ou falha no put_record
            return {
                "statusCode": 400,
                "body": json.dumps(
                    "Failed to send some/all states to Kinesis "
                    "(check KINESIS_STREAM env var and Lambda logs)"
                ),
            }

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Flight data ingestion completed successfully",
                    "states_processed": len(json_resultado["states"]),
                    "timestamp": json_resultado["timestamp"],
                }
            ),
        }
    except Exception as e:
        logger.error(f"Lambda handler error: {e}")
        return {"statusCode": 500, "body": json.dumps(f"Error: {str(e)}")}


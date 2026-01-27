##################################################
# Lambda function to ingest flight data from OpenSky API and send to Kinesis Data Stream

# Método	Descrição

# get_states(bounding_box=None)	
#     Recupera vetores de estado de aeronaves para um tempo determinado. Opcionalmente filtra por uma caixa delimitadora (bounding box)

# get_own_states(time=0)	
#     Recupera vetores de estado apenas dos seus próprios sensores

# authenticate(auth, contributing_user=False)	
#     Autentica o usuário com BasicAuth. Se contributing_user=True, você recebe créditos extras

# calculate_credit_costs(bounding_box)	
#     Calcula quantos créditos uma requisição vai custar

# remaining_credits()	
#     Retorna o saldo de créditos disponíveis

# get_bounding_box(latitude, longitude, radius)	
#     Cria uma caixa delimitadora com base em latitude, longitude e raio

# close()	
#     Fecha a sessão HTTP


# Propriedades Disponíveis:
# api_host - Host da API
# request_timeout - Timeout das requisições
# session - Sessão HTTP usada
# is_authenticated - Verifica se está autenticado
# is_contributing_user - Verifica se é usuário contribuidor
# opensky_credits - Número de créditos disponíveis
# timezone - Timezone configurado

##################################################

import json
import boto3
import os
from datetime import datetime
from python_opensky import OpenSky
from aiohttp import BasicAuth
import asyncio
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS Secrets Manager client
secrets_client = boto3.client('secretsmanager')


def convert_states_response_to_json(states_response):
    """
    Converte um objeto StatesResponse em uma estrutura JSON.
    
    Args:
        states_response: Objeto StatesResponse do python_opensky
        
    Returns:
        dict: Estrutura JSON com os dados dos voos
    """
    json_data = {
        "timestamp": datetime.now().isoformat(),
        "total_states": len(states_response.states) if states_response.states else 0,
        "states": []
    }
    
    if states_response.states:
        for state in states_response.states:
            state_dict = {
                "icao24": state.icao24,
                "callsign": state.callsign.strip() if state.callsign else None,
                "origin_country": state.origin_country,
                "time_position": state.time_position,
                "last_contact": state.last_contact,
                "longitude": state.longitude,
                "latitude": state.latitude,
                "geo_altitude": state.geo_altitude,
                "on_ground": state.on_ground,
                "velocity": state.velocity,
                "true_track": state.true_track,
                "vertical_rate": state.vertical_rate,
                "barometric_altitude": state.barometric_altitude,
                "transponder_code": state.transponder_code,
                "special_purpose_indicator": state.special_purpose_indicator,
                "position_source": str(state.position_source),
                "category": str(state.category)
            }
            # Filtra apenas voos do Brasil
            if state.origin_country == "Brazil":
                json_data["states"].append(state_dict)
    
    return json_data


def send_state_to_kinesis(state_dict, stream_name):
    """
    Sends a single state vector to a Kinesis data stream.
    
    Args:
        state_dict (dict): A state vector dictionary
        stream_name (str): Name of the Kinesis stream
    """
    kinesis_client = boto3.client('kinesis')
    
    try:
        response = kinesis_client.put_record(
            StreamName=stream_name,
            Data=json.dumps(state_dict),
            PartitionKey=state_dict['icao24']  # Use ICAO24 as partition key
        )
        logger.info(f"State {state_dict['icao24']} sent to Kinesis successfully")
        return response
    except Exception as e:
        logger.error(f"Error sending state to Kinesis: {e}")
        return None


def send_states_to_kinesis(json_resultado, stream_name):
    """
    Sends all state vectors from json_resultado to Kinesis stream.
    
    Args:
        json_resultado (dict): Output from convert_states_response_to_json()
        stream_name (str): Name of the Kinesis stream
    """
    for state in json_resultado['states']:
        send_state_to_kinesis(state, stream_name)
    logger.info(f"Sent {json_resultado['total_states']} states to Kinesis stream '{stream_name}'")


async def get_opensky_states():
    """
    Fetch flight states from OpenSky API with authentication.
    
    Returns:
        StatesResponse: Object containing state vectors
    """
    try:
        # Get OpenSky credentials from AWS Secrets Manager
        secret_arn = os.environ.get('OPENSKY_SECRET_ARN')
        
        if not secret_arn:
            logger.error("Missing OPENSKY_SECRET_ARN in environment variables")
            return None
        
        # Retrieve secret from AWS Secrets Manager
        try:
            secret_response = secrets_client.get_secret_value(SecretId=secret_arn)
            secret_data = json.loads(secret_response['SecretString'])
            user = secret_data.get('username')
            password = secret_data.get('password')
        except Exception as e:
            logger.error(f"Error retrieving OpenSky credentials from Secrets Manager: {e}")
            return None
        
        if not user or not password:
            logger.error("Missing username or password in Secrets Manager secret")
            return None
        
        api = OpenSky()
        auth = BasicAuth(user, password)
        api.authenticate(auth)
        
        states = await api.get_states()
        logger.info(f"Retrieved {len(states.states) if states.states else 0} states from OpenSky API")
        return states
    except Exception as e:
        logger.error(f"Error fetching states from OpenSky API: {e}")
        return None


def lambda_handler(event, context):
    """
    Main Lambda handler that orchestrates the flight data ingestion pipeline.
    """
    try:
        # Get Kinesis stream name from environment
        stream_name = os.environ.get('KINESIS_STREAM')
        if not stream_name:
            logger.error("KINESIS_STREAM environment variable not set")
            return {
                'statusCode': 400,
                'body': json.dumps('Missing KINESIS_STREAM environment variable')
            }
        
        # Fetch states from OpenSky API
        logger.info("Starting to fetch states from OpenSky API...")
        states = asyncio.run(get_opensky_states())
        
        if not states:
            logger.warning("No states retrieved from OpenSky API")
            return {
                'statusCode': 500,
                'body': json.dumps('Failed to retrieve states from OpenSky API')
            }
        
        # Convert states to JSON format
        logger.info("Converting states to JSON format...")
        json_resultado = convert_states_response_to_json(states)
        
        # Send states to Kinesis
        logger.info(f"Sending {json_resultado['total_states']} states to Kinesis stream '{stream_name}'...")
        send_states_to_kinesis(json_resultado, stream_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Flight data ingestion completed successfully',
                'states_processed': json_resultado['total_states'],
                'timestamp': json_resultado['timestamp']
            })
        }
    
    except Exception as e:
        logger.error(f"Lambda handler error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
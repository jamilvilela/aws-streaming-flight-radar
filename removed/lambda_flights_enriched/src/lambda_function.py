import logging
from removed.lambda_flights_enriched.src.module.flights import TransformFlights

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    
    tf = TransformFlights(event)
    output = tf.transform()
    
    if not output:
        logger.info("No records to send to output stream")
        return
    else:
        logger.info(f"Enriquecimento concluído, preparando para enviar {len(output)} registros")
        return {"records": output}
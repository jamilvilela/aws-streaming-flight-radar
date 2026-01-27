import hashlib

def lambda_handler(event, context):
    flights = get_flight_data()
    
    # Particionamento por região geográfica
    for flight in flights:
        partition_key = hashlib.sha256(
            f"{flight['latitude']}-{flight['longitude']}".encode()
        ).hexdigest()
        
        kinesis.put_record(
            StreamName=os.environ['KINESIS_STREAM'],
            Data=json.dumps(flight),
            PartitionKey=partition_key
        )
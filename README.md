# aws-streaming-flight-radar
aws-streaming-flight-radar


Fluxo de Dados:
EventBridge aciona Lambdas de ingestão periodicamente

Lambdas de ingestão:

Coletam dados dos endpoints da API

Escrevem em seus respectivos Kinesis Streams

Kinesis aciona Lambdas de processamento

Lambdas de processamento:

Transformam os dados

Armazenam nas tabelas DynamoDB correspondentes


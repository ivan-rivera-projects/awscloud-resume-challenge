def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',  # Allow all origins
            'Access-Control-Allow-Methods': 'OPTIONS, POST',  # Allow all methods
            'Access-Control-Allow-Headers': 'Content-Type',  # Allow all headers
        },
        'body': ''
    }

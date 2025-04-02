import json
import boto3
import os
import logging

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    dynamodb_client = boto3.client('dynamodb')
    # Get table name from environment variable set by Terraform
    # Fallback only needed if Terraform env var is missing
    table_name = os.environ.get('TABLE_NAME', 'CloudResume-Visit') # Reads TABLE_NAME env var
    item_id = '1' # The specific item ID for the counter

    try:
        # 2. Retrieve the 'views' value
        logger.info(f"Attempting to get item '{item_id}' from table '{table_name}'")
        get_item_response = dynamodb_client.get_item(
            TableName=table_name,
            Key={'id': {'S': item_id}}
        )

        if 'Item' in get_item_response:
            # Item exists, get old views and increment
            # Use .get() with default for 'views' attribute to handle missing attribute gracefully
            old_views = int(float(get_item_response['Item'].get('views', {'N': '0'})['N']))
            new_views = old_views + 1
            logger.info(f"Retrieved old views: {old_views}. New views: {new_views}")
        else:
            # Item doesn't exist, initialize views to 1
            logger.warning(f"Item '{item_id}' not found in table '{table_name}'. Initializing views to 1.")
            new_views = 1

        # 3. Update the item (or create if it didn't exist)
        logger.info(f"Attempting to update item '{item_id}' in table '{table_name}' with views = {new_views}")
        dynamodb_client.update_item(
            TableName=table_name,
            Key={'id': {'S': item_id}},
            UpdateExpression='SET #v = :val',
            ExpressionAttributeNames={'#v': 'views'},
            ExpressionAttributeValues={':val': {'N': str(new_views)}}
        )
        logger.info("Successfully updated item.")

    except Exception as e:
        logger.error(f"Error interacting with DynamoDB: {e}")
        # Return an error response if something goes wrong
        return {
            'statusCode': 500,
            'headers': {
                # Add CORS headers even for errors, in case the browser needs them
                'Access-Control-Allow-Origin': '*', # Consider restricting this via API Gateway/Lambda URL config
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET, OPTIONS' # Methods allowed by this function
            },
            'body': json.dumps({'error': 'Internal Server Error accessing view count'})
        }

    # 4. Construct successful response content
    result = str(new_views)

    # Return successful response with CORS headers
    # Note: CORS for Lambda Function URLs is best configured in the TF resource `aws_lambda_function_url`
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*', # Consider restricting this
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET, OPTIONS'
        },
        'body': result
    }
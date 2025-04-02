import json
import boto3
import uuid
import os
import logging
from datetime import datetime

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB and SES clients
# Use boto3.resource for DynamoDB for higher-level abstraction if preferred
dynamodb_client = boto3.client('dynamodb')
ses_client = boto3.client('ses')

# Get table name and notification email from environment variables set by Terraform
TABLE_NAME = os.environ.get('TABLE_NAME', 'CloudResume-Feedback') # Reads TABLE_NAME env var
NOTIFICATION_EMAIL = os.environ.get('NOTIFICATION_EMAIL', 'default-email@example.com') # Reads NOTIFICATION_EMAIL env var

def lambda_handler(event, context):
    # Define CORS headers - Apply these to all responses
    cors_headers = {
        'Access-Control-Allow-Origin': '*',  # Be specific in production, e.g., 'https://yourdomain.com'
        'Access-Control-Allow-Methods': 'OPTIONS, POST',
        'Access-Control-Allow-Headers': 'Content-Type',
    }

    try:
        # Log the incoming event (optional, be mindful of sensitive data)
        # logger.info(f"Received event: {json.dumps(event)}")

        # Parse the incoming request body
        # Handle potential missing body or invalid JSON
        try:
            body = json.loads(event.get('body', '{}'))
            if not isinstance(body, dict):
                 raise ValueError("Request body is not a valid JSON object")
        except json.JSONDecodeError:
            logger.error("Failed to decode JSON body")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid JSON format in request body.'})
            }
        except ValueError as ve:
             logger.error(f"Invalid request body: {ve}")
             return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': str(ve)})
            }


        name = body.get('name')
        email = body.get('email')
        message = body.get('message')

        # Validate input fields
        if not name or not email or not message:
            logger.warning("Validation failed: Missing required fields.")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'All fields (name, email, message) are required.'})
            }

        # Prepare the data to store in DynamoDB
        submission_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        feedback_item = {
            'SubmissionId': {'S': submission_id},
            'Name': {'S': name},
            'Email': {'S': email},
            'Message': {'S': message},
            'Timestamp': {'S': timestamp}
        }

        # Store data in DynamoDB
        logger.info(f"Attempting to put item in DynamoDB table: {TABLE_NAME}")
        dynamodb_client.put_item(
            TableName=TABLE_NAME,
            Item=feedback_item
        )
        logger.info(f"Successfully stored feedback with SubmissionId: {submission_id}")

        # Send notification email via SES
        email_subject = f"New Feedback Submission from {name}"
        email_body = f"New feedback submitted via Cloud Resume:\n\nName: {name}\nEmail: {email}\nTimestamp: {timestamp}\n\nMessage:\n{message}\n"

        logger.info(f"Attempting to send SES notification to: {NOTIFICATION_EMAIL}")
        ses_client.send_email(
            Source=NOTIFICATION_EMAIL, # Must be a verified SES identity
            Destination={'ToAddresses': [NOTIFICATION_EMAIL]},
            Message={
                'Subject': {'Data': email_subject, 'Charset': 'UTF-8'},
                'Body': {
                    'Text': {'Data': email_body, 'Charset': 'UTF-8'}
                    # Optional: Add HTML body
                    # 'Html': {'Data': '<html><body>HTML content</body></html>', 'Charset': 'UTF-8'}
                }
            }
        )
        logger.info("Successfully sent SES notification.")

        # Return a successful response
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({'message': 'Feedback submitted successfully.'})
        }

    except Exception as e:
        # Log the detailed error
        logger.exception(f"An unexpected error occurred: {e}") # logger.exception includes stack trace
        # Return a generic error response
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Internal Server Error. Failed to process feedback.'})
        }
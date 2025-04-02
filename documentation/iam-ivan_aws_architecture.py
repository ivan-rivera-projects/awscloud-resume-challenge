from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import Route53, CloudFront
from diagrams.aws.storage import S3
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.network import APIGateway # Corrected import location
from diagrams.aws.security import WAF, ACM # Added ACM import
# SES import removed as we'll use Custom
from diagrams.aws.general import Users
from diagrams.custom import Custom # Import Custom class

# Define the diagram
with Diagram("iam-ivan.com AWS Architecture", show=False, direction="LR"):
    # User accessing the system
    user = Users("Website Users")
    admin_user = Users("Admin Email") # Added recipient user

    # DNS
    route53 = Route53("Route 53 (DNS)")

    # Edge Network (CloudFront)
    with Cluster("Edge"):
        cloudfront = CloudFront("CloudFront (CDN)")
        # WAF is conditionally associated in Terraform, but shown definitively here
        waf = WAF("AWS WAF")
        acm = ACM("ACM (SSL/TLS Certificate)") # Added ACM node

    # Static Content Storage
    with Cluster("Storage"):
        s3_bucket = S3("S3 Bucket (Website Files)")

    # Backend API and Compute
    with Cluster("Backend API"):
        api_gw = APIGateway("API Gateway (Feedback API)")

        with Cluster("Compute & Messaging"): # Renamed cluster slightly
            lambda_visitor = Lambda("Lambda (Visitor Counter)")
            lambda_feedback = Lambda("Lambda (Feedback Form)")
            lambda_cors = Lambda("Lambda (CORS Handler)")
            # Use Custom node with the saved SVG icon
            ses = Custom("SES (Email Service)", "./icons/ses.svg")

        with Cluster("Database"):
            dynamodb_visits = Dynamodb("DynamoDB (Visitor Count)")
            dynamodb_feedback = Dynamodb("DynamoDB (Feedback Data)")

    # Define Connections
    user >> Edge(label="HTTPS", color="black", penwidth="2.0") >> route53
    route53 >> Edge(label="DNS Resolution", color="black", penwidth="2.0") >> cloudfront
    acm >> Edge(label="Provides Cert", style="dashed", color="darkgrey", penwidth="1.5") >> cloudfront # Added ACM -> CloudFront edge

    # CloudFront -> WAF -> S3/API GW
    # Assuming WAF is potentially active
    cloudfront >> Edge(label="Request", color="black", penwidth="2.0") >> waf
    # Origin 1: S3 Bucket (via OAC - represented implicitly by the connection)
    waf >> Edge(label="Static Content Request", color="darkgreen", penwidth="2.0") >> s3_bucket
    # Origin 2: API Gateway (for /feedback path) - Note: CloudFront doesn't directly call API GW here, user's browser does via CloudFront URL
    # A more accurate flow for API: User -> CloudFront -> User's Browser -> API GW
    # Simplified flow for diagram:
    waf >> Edge(label="API Request (/feedback)", color="purple", penwidth="2.0") >> api_gw

    # API Gateway -> Lambdas
    api_gw >> Edge(label="POST /feedback", color="purple", penwidth="2.0") >> lambda_feedback
    api_gw >> Edge(label="OPTIONS /feedback", color="purple", penwidth="2.0") >> lambda_cors

    # Website JS -> Visitor Counter Lambda (via Function URL - simplified connection)
    # Representing the direct call from the browser JS fetched via CloudFront
    user >> Edge(label="Visitor Count API Call (Function URL)", style="dashed", color="blue", penwidth="2.0") >> lambda_visitor

    # Lambdas -> DynamoDB
    lambda_visitor >> Edge(label="Update/Read Count", color="blue", penwidth="2.0") >> dynamodb_visits
    lambda_feedback >> Edge(label="Write Feedback", color="purple", penwidth="2.0") >> dynamodb_feedback
    lambda_feedback >> Edge(label="Send Email", color="orange", penwidth="2.0") >> ses # Added Lambda -> SES edge
    ses >> Edge(label="Notification", style="dashed", color="orange", penwidth="2.0") >> admin_user # Added SES -> Admin edge
from elasticsearch import Elasticsearch, helpers
from faker import Faker
import random
import time
import logging

# Instantiate the Faker generator
fake = Faker()

# Create a connection
es = Elasticsearch([{'host': 'localhost', 'port': 9200, 'scheme': 'http'}], basic_auth=('ds2user', 'ds2password'))

# Function to create a fake "document"
def create_fake_log():
    return {
        "reqTimeSec": str((time.time() - random.uniform(1, 2592000))),
        "UA": fake.user_agent(),
        "accLang": "-",
        "billingRegion": str(random.randint(1, 10)),
        "breadcrumbs": "-",
        "bytes": str(random.randint(500, 100000)),
        "cacheStatus": str(random.randint(0, 1)),
        "cacheable": str(random.randint(0, 1)),
        "city": fake.city(),
        "cliIP": fake.ipv4(),
        "cookie": "-",
        "country": fake.country_code(),
        "cp": str(random.randint(1000000, 2000000)),
        "customField": "ctt:0",
        "dnsLookupTimeMSec": "-",
        "edgeIP": fake.ipv4(),
        "errorCode": "-",
        "ewExecutionInfo": "-",
        "ewUsageInfo": "-",
        "lastByte": str(random.randint(0, 1)),
        "maxAgeSec": "-",
        "objSize": str(random.randint(500, 100000)),
        "overheadBytes": str(random.randint(500, 700)),
        "proto": random.choice(['HTTP/1.1', 'HTTP/2']),
        "queryStr": "-",
        "range": "-",
        "referer": fake.uri(),
        "reqEndTimeMSec": str(random.randint(100, 200)),
        "reqHost": fake.domain_name(),
        "reqId": str(random.randint(100000, 200000)),
        "reqMethod": random.choice(['GET', 'POST', 'PUT', 'DELETE']),
        "reqPath": fake.uri(),
        "reqPort": "443",
        "rspContentLen": str(random.randint(500, 100000)),
        "rspContentType": random.choice(['text/html', 'application/json']),
        "securityRules": "-",
        "serverCountry": fake.country_code(),
        "state": fake.state(),
        "statusCode": random.choice(['200', '404', '500']),
        "streamId": str(random.randint(1, 100)),
        "tlsOverheadTimeMSec": str(random.randint(100, 200)),
        "tlsVersion": "TLSv1.2",
        "totalBytes": str(random.randint(100000, 200000)),
        "transferTimeMSec": str(random.randint(0, 10)),
        "turnAroundTimeMSec": str(random.randint(0, 10)),
        "uncompressedSize": "-",
        "version": "5",
        "xForwardedFor": "-",
    }

# Total number of documents to be indexed
num_docs = 10000

# Number of documents to be generated and indexed at once
batch_size = 5000

# Index name
index_name = 'datastream2'

# Number of times the batch operation should run
num_batches = num_docs // batch_size

# Maximum number of retries
max_retries = 3

# Setup the logger
logging.basicConfig(level=logging.ERROR)
logger = logging.getLogger(__name__)

# Generate the documents in batches and index them
for _ in range(num_batches):
    actions = ({
        "_index": index_name,
        "_source": create_fake_log(),
    } for _ in range(batch_size))
    
    for attempt in range(max_retries):
        try:
            helpers.bulk(es, actions, chunk_size=batch_size)
            break
        except Exception as e:
            if attempt < max_retries - 1:  # i.e. not the final attempt
                time.sleep(10)  # wait for 10 seconds before trying again
            else:
                logger.error(f"Failed to index documents after {max_retries} attempts.")
                logger.error(str(e))

print(f"Indexed {num_docs} documents.")

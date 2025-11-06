import crypt
import datetime
import http.client
import json
import logging
import os
import random
from zoneinfo import ZoneInfo

logger = logging.getLogger()


seed = os.environ["SEED"]
seed = int(seed)
random.seed(seed)


def call_time_api(timezone):
    connection = http.client.HTTPSConnection("worldtimeapi.org")

    headers = {"Accept": "application/json"}

    connection.request("GET", f"/api/timezone/{timezone}", None, headers)

    response = connection.getresponse()
    result = json.loads(response.read().decode())

    return result


def handler(event, context):
    logger.info("received processing event {!r}".format(event))

    timezone = "America/New_York"

    # call out to an external service to validate the time
    result = call_time_api(timezone)

    logger.info(f"remote datetime {result["datetime"]}")

    remote_datetime = datetime.datetime.strptime(
        result["datetime"],
        "%Y-%m-%dT%H:%M:%S.%f%z",
    )

    local_datetime = datetime.datetime.now(ZoneInfo(timezone))

    # give some wiggle room
    is_time_valid = False

    jitter = datetime.timedelta(seconds=5)
    lower_bound = local_datetime - jitter
    upper_bound = local_datetime + jitter

    if lower_bound <= remote_datetime and remote_datetime <= upper_bound:
        is_time_valid = True

    # do some constant time validation
    crypt.crypt(result["datetime"])

    # in pharmacy benefits, the prices are just made up
    return {
        "price": random.randint(1, 10000),
        "timestamp": result["datetime"],
        "is_time_valid": is_time_valid,
    }


if __name__ == "__main__":
    print(handler({}, None))

import json
import base64
from datetime import datetime, timezone

class TransformFlights:
    def __init__(self, event):
        self.event = event

    def transform(self):
        output = []

        for record in self.event["records"]:
            raw = record["data"]
            rec_data = json.loads(
                base64.b64decode(raw).decode("utf-8")
            )

            if rec_data.get("latitude") is None or rec_data.get("longitude") is None:
                result = {
                    "recordId:": record["recordId"],
                    "result": "Dropped"
                }
            else:
                rec_enriched = {
                    "icao24":         rec_data.get("icao24"),
                    "callsign":       rec_data.get("callsign"),
                    "origin_country": rec_data.get("origin_country"),
                    "latitude":       rec_data.get("latitude"),
                    "longitude":      rec_data.get("longitude"),
                    "altitude":       rec_data.get("altitude"),
                    "velocity":       rec_data.get("velocity"),
                    "heading":        rec_data.get("heading"),
                    "last_contact":   rec_data.get("last_contact"),
                    "event_time":     datetime.now(timezone.utc).isoformat(),
                    "location":       f"{rec_data.get('latitude')},{rec_data.get('longitude')}",
                    "event_date":     datetime.now(timezone.utc).date().isoformat()
                }
                result = {
                    "recordId:": record["recordId"],
                    "result": "Ok",
                    "data": base64.b64encode(json.dumps(rec_enriched).encode("utf-8")).decode("utf-8")
                }

            output.append(result)
        return output
import json

from flask import Response, request
from slugify import slugify


def main():
    # flask is provided by Fission's python environment; slugify is vendored into the zip by build.sh
    text = request.args.get("text")
    if not text:
        return Response(
            json.dumps({"error": "query parameter 'text' is required"}),
            status=400,
            mimetype="application/json",
        )
    return Response(json.dumps({"text": text, "slug": slugify(text)}), mimetype="application/json")

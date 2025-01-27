import json
import csv
import os
import pandas as pd

def flatten_json(nested_json, parent_key='', sep='_'):
    items = []
    for k, v in nested_json.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_json(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)

def horreumjson2csv(input_json, output_csv, field_name, field_value):
    with open(input_json, 'r') as f:
        data = json.load(f)

    flat_data = [flatten_json(item) for item in data]

    fieldnames = set()
    for item in flat_data:
        fieldnames.update(item.keys())
    fieldnames = list(fieldnames)

    for item in flat_data:
        item[field_name] = field_value
    if field_name not in fieldnames:
        fieldnames.append(field_name)

    with open(output_csv, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for item in flat_data:
            row = {field: item.get(field, '') for field in fieldnames}
            writer.writerow(row)

from google.cloud import bigquery
import json
import os
from datetime import datetime

def analyze_bigquery_datasets():
    client = bigquery.Client()
    
    # Create output directory if it doesn't exist
    output_dir = "analytics/bigquery_analysis/dataset_analysis"
    os.makedirs(output_dir, exist_ok=True)
    
    # Get all datasets
    datasets = list(client.list_datasets())
    
    # Create a summary report
    summary = {
        "generated_at": datetime.now().isoformat(),
        "total_datasets": len(datasets),
        "datasets": []
    }
    
    for dataset in datasets:
        dataset_ref = client.get_dataset(dataset.reference)
        tables = list(client.list_tables(dataset_ref))
        
        dataset_info = {
            "dataset_id": dataset.dataset_id,
            "description": dataset_ref.description,
            "created": dataset_ref.created.isoformat(),
            "modified": dataset_ref.modified.isoformat(),
            "total_tables": len(tables),
            "tables": []
        }
        
        for table in tables:
            table_ref = client.get_table(table.reference)
            schema = [
                {
                    "name": field.name,
                    "type": field.field_type,
                    "description": field.description,
                    "mode": field.mode
                }
                for field in table_ref.schema
            ]
            
            table_info = {
                "table_id": table.table_id,
                "description": table_ref.description,
                "created": table_ref.created.isoformat(),
                "modified": table_ref.modified.isoformat(),
                "schema": schema,
                "row_count": table_ref.num_rows
            }
            
            dataset_info["tables"].append(table_info)
        
        summary["datasets"].append(dataset_info)
        
        # Save individual dataset report
        with open(f"{output_dir}/{dataset.dataset_id}_analysis.json", "w") as f:
            json.dump(dataset_info, f, indent=2)
    
    # Save summary report
    with open(f"{output_dir}/summary_report.json", "w") as f:
        json.dump(summary, f, indent=2)
    
    # Generate markdown report
    with open(f"{output_dir}/analysis_report.md", "w") as f:
        f.write("# BigQuery Dataset Analysis Report\n\n")
        f.write(f"Generated at: {summary['generated_at']}\n\n")
        f.write(f"## Summary\n")
        f.write(f"- Total Datasets: {summary['total_datasets']}\n\n")
        
        for dataset in summary["datasets"]:
            f.write(f"## Dataset: {dataset['dataset_id']}\n")
            f.write(f"- Description: {dataset['description']}\n")
            f.write(f"- Created: {dataset['created']}\n")
            f.write(f"- Modified: {dataset['modified']}\n")
            f.write(f"- Total Tables: {dataset['total_tables']}\n\n")
            
            f.write("### Tables\n")
            for table in dataset["tables"]:
                f.write(f"#### {table['table_id']}\n")
                f.write(f"- Description: {table['description']}\n")
                f.write(f"- Row Count: {table['row_count']}\n")
                f.write("\nColumns:\n")
                for field in table["schema"]:
                    f.write(f"- {field['name']} ({field['type']})")
                    if field["description"]:
                        f.write(f" - {field['description']}")
                    f.write("\n")
                f.write("\n")

if __name__ == "__main__":
    analyze_bigquery_datasets() 
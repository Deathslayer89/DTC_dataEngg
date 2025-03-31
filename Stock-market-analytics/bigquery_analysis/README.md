# BigQuery Dataset Analysis Tool

This tool analyzes all datasets and tables in your BigQuery project and generates detailed reports about their structure and content.

## Setup

1. Make sure you have Python 3.7+ installed
2. Install the required dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Ensure you have proper Google Cloud credentials set up:
   - Either set the GOOGLE_APPLICATION_CREDENTIALS environment variable pointing to your service account key file
   - Or use gcloud CLI authentication

## Usage

Run the analysis script:
```bash
python analyze_bigquery.py
```

## Output

The script will generate the following files in the `dataset_analysis` directory:

1. `summary_report.json` - A comprehensive JSON report of all datasets and tables
2. `analysis_report.md` - A human-readable markdown report
3. Individual JSON files for each dataset (named `{dataset_id}_analysis.json`)

## Report Contents

The reports include:
- Dataset metadata (ID, description, creation date, modification date)
- Table metadata (ID, description, row count, creation date, modification date)
- Detailed schema information for each table
- Column descriptions and types

## Using the Analysis for Looker Dashboards

After running the analysis:
1. Review the `analysis_report.md` to understand your data structure
2. Identify key metrics and dimensions that would be valuable for dashboards
3. Use the schema information to create appropriate Looker explores and views
4. Consider creating new dashboards based on the relationships between different tables

## Recommendations for Dashboard Organization

Based on the analysis, consider organizing your dashboards into these categories:

1. **Overview Dashboards**
   - High-level metrics across all datasets
   - Key performance indicators
   - System health metrics

2. **Dataset-Specific Dashboards**
   - Detailed analysis of each major dataset
   - Dataset-specific metrics and trends
   - Data quality indicators

3. **Cross-Dataset Analysis**
   - Combined metrics from related datasets
   - Correlation analysis
   - Business process flows

4. **Operational Dashboards**
   - Data pipeline health
   - Processing metrics
   - Error rates and issues 
# Stock Performance Dashboard

## Overview
This dashboard provides real-time insights into stock performance metrics derived from our DBT models and BigQuery data. It visualizes key performance indicators, trends, and comparisons to help stakeholders make informed investment decisions.

## Data Sources
- BigQuery Table: `project.dataset.mart_stock_performance`
- Refresh Frequency: Daily at market close

## Dashboard Components

### 1. Stock Price Trends
- **Visualization Type**: Line chart
- **Metrics**: Daily closing price, moving averages (7-day, 30-day)
- **Dimensions**: Date, ticker symbol
- **Filters**: Date range, ticker selection

### 2. Volume Analysis
- **Visualization Type**: Bar chart with line overlay
- **Metrics**: Trading volume, price
- **Dimensions**: Date, ticker symbol
- **Filters**: Date range, volume thresholds

### 3. Comparative Performance
- **Visualization Type**: Area chart
- **Metrics**: Normalized price (% change)
- **Dimensions**: Date, ticker symbol
- **Filters**: Benchmark selection, date range

### 4. Key Metrics Scorecard
- **Visualization Type**: Scorecards
- **Metrics**: YTD return, volatility, beta, Sharpe ratio
- **Dimensions**: Ticker symbol
- **Filters**: Date range

## Implementation Steps

1. **LookML Model Configuration**:
   - Create a new LookML model connected to the `mart_stock_performance` view
   - Define dimensions and measures for price, volume, and calculated metrics

2. **Dashboard Setup**:
   - Create a new dashboard in Looker
   - Add tiles for each visualization component
   - Configure filters and parameters

3. **Data Testing**:
   - Verify data accuracy against source systems
   - Test all filters and interactions

4. **Scheduling**:
   - Set up automatic refresh after daily DBT jobs complete
   - Configure user subscriptions for daily/weekly reports

## Access Control
- Finance team: Full access
- Executive team: View access
- General users: View access with limited filters 
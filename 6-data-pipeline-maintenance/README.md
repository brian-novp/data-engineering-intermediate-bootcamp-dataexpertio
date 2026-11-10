# Week 5 Data Pipeline Maintenance

### Homework

Imagine you're in a group of 4 data engineers, you will be in charge of creating the following things:

You are in charge of managing these 5 pipelines that cover the following business areas:
 
- Profit
 - Unit-level profit needed for experiments
 - Aggregate profit reported to investors
- Growth
 - Aggregate growth reported to investors
 - Daily growth needed for experiments
- Engagement 
 - Aggregate engagement reported to investors

You are in charge of figuring out the following things:

- Who is the primary and secondary owners of these pipelines?
- What is an on-call schedule that is fair
  - Think about holidays too!
- Creating run books for all pipelines that report metrics to investors
  - What could potentially go wrong in these pipelines?
  - (you don't have to recommend a course of action though since this is an imaginatione exercise)
<br><br><br><br>  


# Data Engineering Pipeline Management

## Pipeline Overview
We are managing 5 key data pipelines that serve various business areas. Each pipeline plays a crucial role in generating insights and metrics for our stakeholders.

### Business Areas and Pipelines

1. **Profit**
   - **Unit-level profit needed for experiments**
   - **Aggregate profit reported to investors**

2. **Growth**
   - **Aggregate growth reported to investors**
   - **Daily growth needed for experiments**

3. **Engagement**
   - **Aggregate engagement reported to investors**

---

## Team Ownership Structure

### Primary and Secondary Owners

| Pipeline                                      | Primary Owner        | Secondary Owner     |
|-----------------------------------------------|----------------------|---------------------|
| Unit-level profit needed for experiments      | Data Engineer 1      | Data Engineer 2     |
| Aggregate profit reported to investors        | Data Engineer 3      | Data Engineer 4     |
| Aggregate growth reported to investors        | Data Engineer 2      | Data Engineer 1     |
| Daily growth needed for experiments            | Data Engineer 4      | Data Engineer 3     |
| Aggregate engagement reported to investors     | Data Engineer 1      | Data Engineer 4     |

---

## On-Call Schedule

### Fair Scheduling Principles

- **Rotation:** Each engineer should have equal exposure to on-call duties.
- **Time Off Considerations:** Schedule rotations to account for holidays and personal time off.

### Proposed On-Call Schedule

| Week                | Data Engineer 1   | Data Engineer 2   | Data Engineer 3   | Data Engineer 4   |
|---------------------|-------------------|-------------------|-------------------|-------------------|
| Week 1              | On-Call           |                   |                   |                   |
| Week 2              |                   | On-Call           |                   |                   |
| Week 3              |                   |                   | On-Call           |                   |
| Week 4              |                   |                   |                   | On-Call           |
| Week 5 (Holiday)    | On-Call           |                   |                   |                   |
| Week 6              |                   | On-Call           |                   |                   |
| Week 7              |                   |                   | On-Call           |                   |
| Week 8              |                   |                   |                   | On-Call           |

*Note: Adjust the schedule based on holiday coverage requirements.*

---

## Run Books for Investor Metrics Pipelines

### Pipeline 1: Unit-level Profit Needed for Experiments
- **What could go wrong?**
  - Data inconsistencies due to source data changes.
  - Missing records affecting experiments.
  - Unexpected downtime of dependent data sources.

### Pipeline 2: Aggregate Profit Reported to Investors
- **What could go wrong?**
  - Errors in aggregation logic could lead to incorrect figures.
  - Connection issues with data storage systems.
  - Failure to capture real-time data impacting reporting.

### Pipeline 3: Aggregate Growth Reported to Investors
- **What could go wrong?**
  - Delayed data arrival leading to outdated metrics.
  - Misalignment of growth indicators with business goals.

### Pipeline 4: Daily Growth Needed for Experiments
- **What could go wrong?**
  - Failure of scheduling jobs due to environment issues.
  - Change in experiment parameters not reflected in data processing.

### Pipeline 5: Aggregate Engagement Reported to Investors
- **What could go wrong?**
  - Aggregation process fails leading to incomplete reports.
  - External services affecting data enrichment processes.

---

## Conclusion
The above structures outline the ownership, on-call schedule, and potential failure points for the key data pipelines. Each member of the team plays a critical role in ensuring the reliability and accuracy of data critical to our stakeholders.


 
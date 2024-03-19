/* Total rows */
SELECT count(*)
FROM austin_crime;

/* Validate if the incident number is unique */
SELECT incident_number,
	count(*)
FROM austin_crime
GROUP BY incident_number
HAVING count(*) > 1;

/* Doing a data sanity check */
-- 1. Comparing the total row count and non-null counts of each column
SELECT count(*) as row_count,
	count(incident_number) as incident_number,
	count(highest_offense_description) as highest_offense_description,
	count(highest_offense_code) as highest_offense_code,
	count(family_violence) as family_violence,
	count(occurred_date_time) as occurred_date_time,
	count(occurred_date) as occurred_date,
	count(occurred_time) as occurred_time,
	count(report_date_time) as report_date_time,
	count(report_date) as report_date,
	count(report_time) as report_time,
	count(location_type) as location_type,
	count(address) as address,
	count(zip_code) as zip_code,
	count(council_district) as council_district,
	count(apd_sector) as apd_sector,
	count(apd_district) as apd_district,
	count(pra) as pra,
	count(census_tract) as census_tract,
	count(clearance_status) as clearance_status,
	count(clearance_date) as clearance_date,
	count(ucr_category) as ucr_category,
	count(category_description) as category_description,
	count(x_coordinate) as x_coordinate,
	count(y_coordinate) as y_coordinate,
	count(latitude) as latitude,
	count(longitude) as longtidue,
	count(location) as location
FROM austin_crime;

-- 2. Validating categorial data
SELECT count(distinct highest_offense_code) as highest_offense_code,
	count(distinct highest_offense_description) as highest_offense_description,
	count(distinct family_violence) as family_violence,
	count(distinct clearance_status) as clearance_status,
	count(distinct ucr_category) as ucr_category,
	count(distinct category_description) as category_description,
	count(distinct zip_code) as zip_code,
	count(distinct council_district) as council_district,
	count(distinct apd_sector) as apd_sector,
	count(distinct apd_district) as apd_district
FROM austin_crime;

-- 3. Validating the range of specific columns
SELECT min(length(zip_code::text)::int) as min_length_zip,
	max(length(zip_code::text)::int) as max_length_zip,
	min(report_date) as max_report_date,
	max(report_date) as max_report_date,
	min(occurred_date_time) as min_occurred_date_time,
	max(occurred_date_time) as max_occurred_date_time,
	min(occurred_date) as min_occurred_date,
	max(occurred_date) as max_occurred_date,
	min(clearance_date) as min_clearance_date,
	max(clearance_date) as max_clearance_date
FROM austin_crime;

/* Ratio of cleared cases to reported cases */
SELECT round(100 * (count(clearance_date)::numeric / count(report_date)), 2) as cleared_report_ratio
FROM austin_crime;

/* Top 10 offenses reported */
SELECT highest_offense_description,
	COUNT(*) as total
FROM austin_crime
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

/* Total incidents by location */
SELECT location_type,
	count(*) as total_incidents
FROM austin_crime
GROUP BY 1
ORDER BY 2 DESC;

/* Total incidents by zip code */
SELECT zip_code,
	count(*) as total_incidents
FROM austin_crime
GROUP BY zip_code
ORDER BY 2 DESC;

/* Number of incidents reported each year in comparison to the previous year */
SELECT t.*,
	-- Calculate the percent change from the preceding year
	round(100 * ((total - lag(total) over(order by year_reported))::numeric / lag(total) over(order by year_reported)),2) as year_percent_change
FROM (
	-- Count the number of incidents by year
	SELECT extract(year from report_date) as year_reported,
		count(*) as total
	FROM austin_crime
	GROUP BY year_reported
) t;

/* Top 3 crimes reported each year */
WITH offenses as (
SELECT extract(year from report_date) as year,
	highest_offense_description,
	count(*) as total
FROM austin_crime
GROUP BY year,
	highest_offense_description
) SELECT *
FROM (
	SELECT dense_rank() over(partition by year order by total desc) as rank, -- Use a window function to rank the count of incidents by reporting year
		t.*
	FROM offenses t
) WHERE rank <= 3;

/* Compare the number of cleared incidents to reported incidents each year */
SELECT extract(year from report_date) as year,
	count(report_date) as total_reported,
	count(clearance_date) as total_cleared,
	round(100 * ((b.total_cleared - a.total_reported)::numeric / a.total_reported), 2) as percent_diff
FROM austin_crime
GROUP BY 1;

/* Counting the reasons why a crime was cleared */
SELECT (case clearance_status when 'C' then 'Arrest' when 'O' then 'Exception' when 'N' then 'Not cleared' else 'No reason provided' end) as clearance_reason, -- Convert the status codes into something more descriptive and count the total incidents by status
	count(*) as total
FROM austin_crime
GROUP BY 1
ORDER BY 2 desc;

/* Incidents cleared by the type of crime reported */
SELECT highest_offense_description,
	count(*) as total_offenses,
	sum(case when coalesce(clearance_status, 'N') <> 'N' then 1 else 0 end) as clearance_total
FROM austin_crime
GROUP BY 1
ORDER BY 2 DESC;

/* Crimes committed in Austin that the FBI considered as the highest offense */
SELECT category_description as ucr_category,
	count(*)
FROM austin_crime
WHERE category_description is not null
GROUP BY 1
ORDER BY 2 DESC;

/* Summary of how long it takes to solve a crime from the day it was reported */
SELECT min(clearance_date - report_date) as min_days
	max(clearance_date - report_date) as max_days,
	avg(clearance_date - report_date) as avg_days,
	percentile_disc(0.5) within group (order by (clearance_date - report_date)) as median_days
FROM austin_crime
WHERE clearance_date is not null;


/* If there's a significant amount null values for a column, imputation might be helpful. 
In this scenario, the amount of null records is very small, which might not be noticeable if we analyze the dataset as a whole, but it might be useful if we break it down by features */

-- # of rows where occurred_date_time is null: 7
SELECT count(*)
FROM austin_crime
WHERE occurred_date_time is null;


-- Imputing the missing occurred_date_time with the median datetime by year and offense code
WITH median_occ_time AS (
SELECT extract(year from occurred_date) as year,
	highest_offense_code,
	-- Calculate the median timestamp for occurred_date_time by year and offense code
	to_char(to_timestamp(percentile_disc(0.5) within group(order by extract(epoch from occurred_date_time::time)::int)) AT TIME ZONE 'UTC', 'HH24:MI:SS') as occ_timestamp
FROM austin_crime
GROUP BY 1, 2
) SELECT incident_number,
	a.highest_offense_code,
	highest_offense_description,
	report_date,
	report_date_time,
	occurred_date,
	-- Replace null occurred_date_time values with a occurred date + the median time calculated from the previous CTE
	coalesce(occurred_date_time,
		to_timestamp(concat(to_char(occurred_date, 'YYYY-MM-DD'), ' ', b.occ_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp) as occurred_date_time 
FROM austin_crime a LEFT JOIN median_occ_time b ON a.highest_offense_code = b.highest_offense_code 
	AND extract(year from a.occurred_date) = b.year
WHERE incident_number IN ( -- Validating the 7 records with null values
	SELECT incident_number
	FROM austin_crime
	WHERE occurred_date_time is null
);

/* Creating a summary statistic table to describe the time elapsed from the crime occurring to being reported */
WITH median_occ_time AS (
SELECT extract(year from occurred_date) as year,
	highest_offense_code,
	to_char(to_timestamp(percentile_cont(0.5) within group(order by extract(epoch from occurred_date_time::time)::int)) AT TIME ZONE 'UTC', 'HH24:MI:SS') as occ_timestamp
FROM austin_crime
GROUP BY 1, 2
), dataset as (
SELECT incident_number,
	a.highest_offense_code,
	highest_offense_description,
	report_date,
	report_date_time,
	occurred_date,
	coalesce(occurred_date_time,
		to_timestamp(concat(to_char(occurred_date, 'YYYY-MM-DD'), ' ', b.occ_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp) as occurred_date_time
FROM austin_crime a LEFT JOIN median_occ_time b ON a.highest_offense_code = b.highest_offense_code 
	AND extract(year from a.occurred_date) = b.year
), stats_offense as (
-- Calculate summary statistics for the length of time (in days) elapsed from the incident occurring to the time it was reported
SELECT highest_offense_description,
	count(*) as offense_count,
	round(max(days_length),2) as max_days,
	round(min(days_length),2) as min_days,
	round(avg(days_length), 2) as avg_days,
	round(stddev_pop(days_length), 2) as std_days,
	round((percentile_cont(0.25) within group (order by days_length))::numeric, 2) as q25_days,
	round((percentile_cont(0.5) within group (order by days_length))::numeric, 2) as q50_days,
	round((percentile_cont(0.75) within group (order by days_length))::numeric, 2) as q75_days
FROM (
	SELECT highest_offense_description,
		extract(epoch from (report_date_time - occurred_date_time)) / 86400 as days_length
	FROM dataset) 
GROUP BY highest_offense_description
)SELECT t.*,
-- Calculating IQR can be used to roughly describe how the length of days are distributed
	(q75_days - q25_days) as iqr,
	q25_days - 1.5 * (q75_days-q25_days) as q1,
	q75_days + 1.5 * (q75_days-q25_days) as q3
FROM stats_offense t;


/* Create a view with the features we need */
CREATE OR REPLACE VIEW v_atx2018_crime AS
WITH median_occ_time AS (
SELECT extract(year from occurred_date) as year,
	highest_offense_code,
	to_char(to_timestamp(percentile_cont(0.5) within group(order by extract(epoch from occurred_date_time::time)::int)) AT TIME ZONE 'UTC', 'HH24:MI:SS') as occ_timestamp
FROM austin_crime
GROUP BY 1, 2
) SELECT incident_number,
highest_offense_description,
upper(family_violence) as family_violence,
occurred_date,
coalesce(occurred_date_time, to_timestamp(concat(to_char(occurred_date, 'YYYY-MM-DD'), ' ', b.occ_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp) as occurred_date_time,
report_date,
report_date_time,
location_type,
zip_code,
clearance_status,
clearance_date,
category_description as ucr_category,
x_coordinate as latitude,
y_coordinate as longitude
FROM austin_crime a LEFT JOIN median_occ_time b ON a.highest_offense_code = b.highest_offense_code
	AND extract(year from occurred_date) = b.year
WHERE extract(year from report_date) >= 2018;
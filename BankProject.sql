/* Case Scenario


1. How many unique nodes are there on the Data Bank system?
2. What is the number of nodes per region?
3. How many customers are allocated to each region?
4. How many days on average are customers reallocated to a different node?
5. What is the median, 80th and 95th percentile for this same reallocation days metric for each region?
6. What is the unique count and total amount for each transaction type?
7. What is the average total historical deposit counts and amounts for all customers?
8. For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?
9. What is the closing balance for each customer at the end of the month?
10. What is the percentage of customers who increase their closing balance by more than 5%?

*/

--Case1--

SELECT COUNT(DISTINCT(node_id)) AS Number_of_Nodes
FROM data_bank.customer_nodes;

--Case 2--
--joined the regions table with the customer table, and used the region name for the grouping--

SELECT 
  dbr.region_name,
  COUNT(node_id) as CountOfNodes
FROM data_bank.customer_nodes dbc
JOIN data_bank.regions dbr
ON dbc.region_id = dbr.region_id
GROUP BY dbr.region_name;


--Case 3--
SELECT 
  dbr.region_name,
  COUNT(DISTINCT(customer_id)) as CountOfCustomers
FROM data_bank.customer_nodes dbc
JOIN data_bank.regions dbr
ON dbc.region_id = dbr.region_id
GROUP BY dbr.region_name
ORDER BY CountOfCustomers DESC;

--Case 4/5--
--This shows the average number of days it takes for each customer to change node, also shows the median, 80th and 95th percentile--
WITH DATEDIFF AS (
    SELECT 
        customer_id,
        region_id,
        node_id,
  		start_date,
  		end_date,
        end_date-start_date AS DateDifference
    FROM data_bank.customer_nodes
  WHERE EXTRACT(YEAR FROM end_date) = 2020 AND EXTRACT(YEAR FROM start_date) = 2020 
)
  	SELECT 
  		
  		ROUND(AVG(DateDifference)) AS AverageDays,
  		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DateDifference) AS MEDIAN_DAYS,
  		PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY DateDifference) AS Percentile80,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DateDifference) AS Percentile95
  	FROM DATEDIFF;


--Case6--
SELECT 
	txn_type,
	COUNT(DISTINCT(customer_id)) AS Count_Of_Transactions,
    CASE 
    	WHEN txn_type = 'deposit' THEN SUM(txn_amount)
        WHEN txn_type = 'withdrawal' THEN SUM(txn_amount)
        WHEN txn_type = 'purchase' THEN SUM(txn_amount)
        ELSE 0
     END  AS Sum_OF_Transactions
    
    
FROM data_bank.customer_transactions
GROUP BY txn_type;

--Case 7--
WITH TotalCustomerDeposits as (
    SELECT 
        customer_id,
        COUNT(customer_id) AS CountOfDeposits,
        SUM(txn_amount) AS SumOfDeposits
    FROM data_bank.customer_transactions
    WHERE txn_type = 'deposit' and customer_id is not null
    GROUP BY customer_id
)
SELECT 
	ROUND(AVG(CountOfDeposits)) AS AverageCountOfDeposits,
    ROUND(AVG(SumOfDeposits)) AS AverageTotalDeposits
FROM TotalCustomerDeposits;

--Case 8--
--Used the CASE statement and CTE complete this excercise. First step was to extract the month from the transaction date, and then count the transactions using the CASE statment--

WITH COUNTOFALLTRANSACTIONS AS (
  
    SELECT 
        customer_id,
        EXTRACT(MONTH FROM txn_date) AS TransactionMonth,
  		CASE WHEN txn_type ='deposit' THEN COUNT(customer_id) ELSE 0 END AS COUNT_OF_DEPOSIT,
        CASE WHEN txn_type ='withdrawal' THEN COUNT(customer_id)ELSE 0 END AS COUNT_OF_WITHDRAWAL,
       CASE WHEN txn_type ='purchase' THEN COUNT(customer_id) ELSE 0 END AS COUNT_OF_PURCHASE
    FROM data_bank.customer_transactions

    GROUP BY TransactionMonth,customer_id,txn_type
 ),
MONTHLYTRANSACTIONCOUNT AS (
      SELECT 
          customer_id,
          transactionmonth,
          SUM(count_of_deposit) AS MonthlyDepositCount,
          SUM(count_of_withdrawal) AS MonthlyWithdrawalCount,
          SUM(count_of_purchase) AS MonthlyPurchaseCount
      FROM COUNTOFALLTRANSACTIONS
      
      GROUP  BY customer_id,transactionmonth
)
SELECT *
FROM MONTHLYTRANSACTIONCOUNT
WHERE monthlydepositcount > 1 AND (monthlywithdrawalcount >= 1 OR monthlypurchasecount >= 1 )
LIMIT 10;

--Case 9--
-- To find the closing balance for each customer at the end of each month, first, I calculated the sum of deposit,withdrawal and purchase--


WITH TransactionBalance AS (
  
    SELECT 
        customer_id,
  		
        EXTRACT(MONTH FROM txn_date) AS TransactionMonth,
  		SUM(CASE WHEN txn_type ='deposit' THEN txn_amount ELSE 0 END )AS SUM_OF_DEPOSIT,
        SUM(CASE WHEN txn_type ='withdrawal' THEN txn_amount ELSE 0 END )AS SUM_OF_WITHDRAWAL,
       SUM(CASE WHEN txn_type ='purchase' THEN txn_amount ELSE 0 END )AS SUM_OF_PURCHASE
    FROM data_bank.customer_transactions
	GROUP BY customer_id,txn_date
),
TotalMonthlyTransaction as (
    SELECT 
        customer_id,
        TransactionMonth,
        SUM(SUM_OF_DEPOSIT) AS TOTALMONTHLYDEPOSIT,
        SUM(SUM_OF_WITHDRAWAL) AS TOTALMONTHLYWITHDRAWAL,
        SUM(SUM_OF_PURCHASE) AS TOTALMONTHPURCHASE


    FROM TransactionBalance
    
    GROUP BY customer_id,TransactionMonth
), --calculated the balance by subtracting withdrawal and purchase from deposit--
MONTHLYBAL AS (
    SELECT 
        *,
        (totalmonthlydeposit-totalmonthlywithdrawal-totalmonthpurchase) AS Transaction_BALANCE

FROM TotalMonthlyTransaction
), -- this CTE uses a window function to make sure the closing balance for a customer in month 1 is added to make the closing balance for month 2--
FinalMonthlyBalance AS (
    SELECT 
        *,
        SUM(Transaction_BALANCE) OVER (PARTITION BY customer_id ORDER BY transactionmonth ) as FinalMonthlyBAlance,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY transactionmonth) AS ROW_INDEX

    from MONTHLYBAL
  
) -- the final result is housed in a temporary table , for easy use in CASE 10--
SELECT *
INTO TEMP TABLE NEW_TABLE
FROM FinalMonthlyBalance;


--CASE 10--
--Used the lead function to place the next closing balance in the column next to the cloing balance, then calculated the percentage difference--
WITH NEXTCLOSINGBALANCE AS (
    SELECT 
        row_index,
        customer_id,
        transactionmonth,
        finalmonthlybalance,
        LEAD(finalmonthlybalance) OVER (PARTITION BY customer_id) AS NEXT_CLOSING_BALANCE
    FROM NEW_TABLE
),
BALANCEDIFFERENCE AS (
    SELECT 
        *,
        ROUND(100*(next_closing_balance-finalmonthlybalance)/finalmonthlybalance) AS PERCENTAGE_DIFF

    FROM NEXTCLOSINGBALANCE
    WHERE next_closing_balance IS NOT NULL AND finalmonthlybalance <> 0
)
SELECT * 
FROM BALANCEDIFFERENCE
WHERE PERCENTAGE_DIFF >= 5
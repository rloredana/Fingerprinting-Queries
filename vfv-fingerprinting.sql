CREATE TEMPORARY TABLE vfv_fingerprint AS
SELECT *
FROM atomic.impressions
WHERE account_id = 10922;

-----------------------------------------------------

CREATE TEMPORARY TABLE match_keys AS
SELECT min(cookie_id) AS master_ind,
       cookie_id,
       CASE
           WHEN len(regexp_substr(custom_9, 'gclid=.*&'))> 0 THEN substring(regexp_substr(custom_9, 'gclid=.*&'), 7, len(regexp_substr(custom_9, 'gclid=.*&'))-7)
           ELSE substring(regexp_substr(custom_9, 'gclid=.*'), 7, len(regexp_substr(custom_9, 'gclid=.*')))
       END AS _ga,
       client_ip_address,
       concat(concat(client_ip_address, left(browser_agent_string, 60)),
              browser_language) AS bkey
FROM vfv_fingerprint
WHERE custom_5='Visitor'
  AND custom_9 like '%gclid=%'
GROUP BY cookie_id,
         _ga,
         client_ip_address,
         bkey;

-----------------------------------------------------

INSERT INTO match_keys
  (SELECT min(cookie_id) AS master_ind, cookie_id, '' AS _ga, client_ip_address, concat(concat(client_ip_address, left(browser_agent_string, 60)), browser_language) AS bkey
   FROM vfv_fingerprint
   WHERE custom_5='Visitor'
     AND custom_9 not like '%gclid=%'
   GROUP BY cookie_id, _ga, client_ip_address, bkey);

-----------------------------------------------------

INSERT INTO match_keys
  (SELECT min(cookie_id) AS master_ind, cookie_id, '' AS _ga, client_ip_address, concat(concat(client_ip_address, left(browser_agent_string, 60)), browser_language) AS bkey
   FROM vfv_fingerprint
   WHERE custom_5 != 'Visitor'
   GROUP BY cookie_id, _ga, client_ip_address, bkey);

-----------------------------------------------------

UPDATE match_keys
SET master_ind = b.master_ind
FROM match_keys AS a
JOIN
  (SELECT _ga,
          min(master_ind) AS master_ind
   FROM match_keys
   WHERE _ga <> ''
   GROUP BY _ga
   HAVING COUNT(*) > 1) AS b ON a._ga = b._ga;

-----------------------------------------------------

UPDATE match_keys
SET bkey = ''
FROM match_keys AS a
JOIN
  (SELECT COUNT(DISTINCT impression_date_time) AS impcnt,
          cookie_id
   FROM atomic.impressions
   GROUP BY cookie_id) AS i ON i.cookie_id = a.cookie_id
WHERE a.bkey <> ''
  AND impcnt > 150;

-----------------------------------------------------

UPDATE match_keys
SET master_ind = b.master_ind
FROM match_keys AS a
JOIN
  (SELECT bkey,
          min(master_ind) AS master_ind
   FROM match_keys
   WHERE bkey <> ''
   GROUP BY bkey
   HAVING COUNT(*) > 1) AS b ON a.bkey=b.bkey;

-----------------------------------------------------

UPDATE vfv_fingerprint
SET cookie_id = b.master_ind
FROM vfv_fingerprint AS a
JOIN match_keys AS b ON a.cookie_id = b.cookie_id;

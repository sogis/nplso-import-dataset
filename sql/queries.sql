/*
SELECT
  row_to_json
  (
    ROW
    (
      t_id, 
      dokumentid, 
      titel, 
      offiziellertitel, 
      abkuerzung, 
      offiziellenr, 
      kanton, 
      gemeinde, 
      publiziertab, 
      rechtsstatus, 
      textimweb, 
      bemerkungen, 
      rechtsvorschrift
    )
  )
FROM
  arp_npl.rechtsvorschrften_dokument


WITH json_docs AS 
(
  SELECT
    t_id, 
    row_to_json(t)::text AS json_dokument
  FROM
  (
    SELECT
      *
    FROM
      arp_npl.rechtsvorschrften_dokument
  ) AS t
)

    
  
SELECT
row_to_json(row(t_id, ))
FROM
arp_npl.rechtsvorschrften_dokument


select row_to_json(t)
from (
  select * from arp_npl.rechtsvorschrften_dokument
) t    
    
*/    
    
/*
SELECT
    *
FROM
    arp_npl.rechtsvorschrften_hinweisweiteredokumente  
*/    

-- Alle Dokumente (die in HinweisWeitereDokumente vorkommen) 
-- als JSON-Objekte (resp. als Text-Repräsentation).
-- Muss noch genauer überlegt werden, wie genau mit JSON hantiert wird.
/*
SELECT
  *
FROM
-- Alle t_id der Dokumente, die in der HinweisWeitereDokumente-Tabelle vorhanden sind.
-- UNION macht gleich das DISTINCT.
(
  SELECT
    ursprung AS dokument_t_id
  FROM 
    arp_npl.rechtsvorschrften_hinweisweiteredokumente
  
  UNION 
  
  SELECT
    hinweis AS dokument_t_id
  FROM 
    arp_npl.rechtsvorschrften_hinweisweiteredokumente
) AS foo
LEFT JOIN 
(
  SELECT
    t_id, 
    row_to_json(t)::text AS json_dokument -- Text-Repräsentation des JSON-Objektes. 
  FROM
  (
    SELECT
      *
    FROM
      arp_npl.rechtsvorschrften_dokument
  ) AS t
) AS bar
ON foo.dokument_t_id = bar.t_id
*/ 

-- Recursive CTE must start with 'WITH'
WITH RECURSIVE x(ursprung, hinweis, parents, last_ursprung, depth) AS 
(
  SELECT 
    ursprung, 
    hinweis, 
    ARRAY[ursprung] AS parents, 
    ursprung AS last_ursprung, 
    0 AS "depth" 
  FROM 
    arp_npl.rechtsvorschrften_hinweisweiteredokumente
  
  UNION ALL
  
  SELECT 
    x.ursprung, 
    x.hinweis, 
    parents||t1.hinweis, 
    t1.hinweis AS last_ursprung, 
    x."depth" + 1
  FROM 
    x 
    INNER JOIN arp_npl.rechtsvorschrften_hinweisweiteredokumente t1 
    ON (last_ursprung = t1.ursprung)
  WHERE 
    t1.hinweis IS NOT NULL
), 
doc_doc_references_all AS 
(
  SELECT 
    ursprung, 
    hinweis, 
    --array_to_string(parents,';'),
    parents,
    depth
  FROM x 
  WHERE 
    depth = (SELECT max(sq."depth") FROM x sq WHERE sq.ursprung = x.ursprung)
),
-- Rekursion liefert alle Möglichkeiten, dh. zum Beispiel
-- auch [3,4]. Wir sind aber nur längster Variante einer 
-- Kasksade interessiert: [1,2,3,4,5].
doc_doc_references AS 
(
  SELECT 
    ursprung,
    a_parents AS dok_dok_referenzen
  FROM
  (
    SELECT DISTINCT ON (a_parents)
      a.ursprung,
      a.parents AS a_parents,
      b.parents AS b_parents
    FROM
      doc_doc_references_all AS a
      LEFT JOIN doc_doc_references_all AS b
      ON a.parents <@ b.parents AND a.parents != b.parents
  ) AS foo
  WHERE b_parents IS NULL
),
-- Alle Dokumente in JSON-Text codiert.
json_documents_all AS 
(
  SELECT
    t_id, 
    row_to_json(t)::text AS json_dokument -- Text-Repräsentation des JSON-Objektes. 
  FROM
  (
    SELECT
      *,
      ('https://geoweb.so.ch/zonenplaene/Zonenplaene_pdf/'||"textimweb")::text AS textimweb_absolut
    FROM
      arp_npl.rechtsvorschrften_dokument
  ) AS t
),
-- Alle Dokumente (die in HinweisWeitereDokumente vorkommen) 
-- als JSON-Objekte (resp. als Text-Repräsentation).
-- Muss noch genauer überlegt werden, wie genau mit JSON hantiert wird.
json_documents_doc_doc_reference AS 
(
  SELECT
    t_id, 
    json_dokument
  FROM
  -- Alle t_id der Dokumente, die in der HinweisWeitereDokumente-Tabelle vorhanden sind.
  -- UNION macht gleich das DISTINCT.
  (
    SELECT
      ursprung AS dokument_t_id
    FROM 
      arp_npl.rechtsvorschrften_hinweisweiteredokumente
    
    UNION 
    
    SELECT
      hinweis AS dokument_t_id
    FROM 
      arp_npl.rechtsvorschrften_hinweisweiteredokumente
  ) AS foo
  LEFT JOIN json_documents_all AS bar
  ON foo.dokument_t_id = bar.t_id
),
-- Mit unnest und späteren group by (aggregieren) geht
-- ziemlich sicher die Reihenfolge der Kaskade / des
-- Bandwurms flöten. Respektive ist nicht sichergestellt.
-- Momentan damit leben.
-- Hierarchie geht verloren: [1, 3] und [1, 5] kann
-- zu [5, 1, 3] werden. -> Es gibt schlussendlich und temporär
-- halt einfache ein Liste mit den Dokumenten-Objekten pro Geometrie 
-- (resp. Typ).
typ_grundnutzung_dokument_ref AS 
(
  SELECT DISTINCT
    --string_agg(json_dokument, ';')
    typ_grundnutzung_dokument.typ_grundnutzung,
    dokument,
    --dok_dok_referenzen
    unnest(dok_dok_referenzen) AS dok_referenz
  FROM
    arp_npl.nutzungsplanung_typ_grundnutzung_dokument AS typ_grundnutzung_dokument
    LEFT JOIN doc_doc_references
    ON typ_grundnutzung_dokument.dokument = doc_doc_references.ursprung
),
typ_grundnutzung_json_dokument AS 
(
  SELECT
    *
  FROM
    typ_grundnutzung_dokument_ref
    LEFT JOIN json_documents_doc_doc_reference
    ON json_documents_doc_doc_reference.t_id = typ_grundnutzung_dokument_ref.dok_referenz
),
typ_grundnutzung_json_dokument_agg AS 
(
  SELECT
    typ_grundnutzung AS typ_grundnutzung_t_id,
    string_agg(json_dokument, ';') AS dokumente
  FROM
    typ_grundnutzung_json_dokument
  GROUP BY
    typ_grundnutzung
),
grundnutzung_geometrie_typ AS
(
  SELECT 
    g.t_datasetname::int4 AS bfs_nr,
    g.t_ili_tid,
    g.name_nummer,
    g.rechtsstatus,
    g.publiziertab,
    g.bemerkungen,
    g.erfasser,
    g.datum,
    g.geometrie,
    g.dokument,
    t.t_id AS typ_t_id,
    t.typ_kt AS typ_typ_kt,
    t.code_kommunal AS typ_code_kommunal,
    t.nutzungsziffer AS typ_nutzungsziffer,
    t.nutzungsziffer_art AS typ_nutzungsziffer_art,
    t.geschosszahl AS typ_geschosszahl,
    t.bezeichnung AS typ_bezeichnung,
    t.abkuerzung AS typ_abkuerzung,
    t.verbindlichkeit AS typ_verbindlichkeit,
    t.bemerkungen AS typ_bemerkungen 
  FROM
    arp_npl.nutzungsplanung_grundnutzung AS g
    LEFT JOIN arp_npl.nutzungsplanung_typ_grundnutzung AS t
    ON g.typ_grundnutzung = t.t_id
)
-- Es muss noch das mögliche zusätzliche Dokument (Geometrie -> Dokument)
-- hinzugefügt werden.
SELECT
  g.bfs_nr,
  g.t_ili_tid,
  g.name_nummer,
  g.rechtsstatus,
  g.publiziertab,
  g.bemerkungen,
  g.erfasser,
  g.datum,
  g.geometrie,
  g.typ_typ_kt AS typ_kt,
  g.typ_code_kommunal,
  g.typ_nutzungsziffer,
  g.typ_nutzungsziffer_art,
  g.typ_geschosszahl,
  g.typ_bezeichnung,
  g.typ_abkuerzung,
  g.typ_verbindlichkeit,
  g.typ_bemerkungen,
  CASE 
    WHEN j.json_dokument IS NOT NULL THEN d.dokumente||';'||j.json_dokument
    ELSE d.dokumente 
  END AS dok_id
FROM  
  grundnutzung_geometrie_typ AS g 
  LEFT JOIN typ_grundnutzung_json_dokument_agg AS d
  ON g.typ_t_id = d.typ_grundnutzung_t_id
  LEFT JOIN json_documents_all AS j
  ON j.t_id = g.dokument;



/*
  SELECT
    typ_grundnutzung,
    array_agg(dok_referenz) AS dok_referenz -- Alle Dokumente t_id, die an einem Typ referenziert sind.
  FROM
  (
    SELECT DISTINCT
      --string_agg(json_dokument, ';')
      typ_grundnutzung_dokument.typ_grundnutzung,
      dokument,
      --dok_dok_referenzen
      unnest(dok_dok_referenzen) AS dok_referenz
    FROM
      arp_npl.nutzungsplanung_typ_grundnutzung_dokument AS typ_grundnutzung_dokument
      LEFT JOIN doc_doc_references
      ON typ_grundnutzung_dokument.dokument = doc_doc_references.ursprung
  ) AS foo
  GROUP BY
    typ_grundnutzung

*/

/*
(
  SELECT
    ursprung, 
    unnest(dok_referenzen) AS dok_t_id,
    json_documents.json_dokument AS json_dokument
  FROM
    hwd_doc_references
    LEFT JOIN json_documents
    
    -- AAAAH kennt er noch nicht -> ausserhalb machen
    ON dok_t_id = json_documents.t_id
) AS s
--GROUP BY
  --ursprung
 */ 
-- OOOODER ERST AM SCHLUSS NACH typ joinen zum string_agg machen, da ein typ auf mehrere dokumente zeige kann...
    
    
    
    
    
  
  


/*
WITH RECURSIVE subordinates AS
(
    SELECT
        t_id,
        ursprung,
        hinweis,
        NULL::text[] AS full_name
        --array_agg(ursprung) AS foo
        --ARRAY[ursprung, hinweis]::text[] AS full_name
        --ursprung::text AS ursprung_full_name
    FROM
        arp_npl.rechtsvorschrften_hinweisweiteredokumente
    --WHERE
      --  ursprung = 974

    UNION 
    
    SELECT
        e.t_id, 
        e.ursprung,
        e.hinweis,
        array_append(full_name, s.ursprung::text)
        --array_agg(e.ursprung)
        --array_append(array_append(full_name, s.hinweis::text), e.hinweis::text)
        --array_append(full_name, s.hinweis::text)
        --(s.ursprung_full_name || '->' || e.ursprung::text) AS ursprung_full_name
    FROM
        arp_npl.rechtsvorschrften_hinweisweiteredokumente AS e
    INNER JOIN
        subordinates s ON s.hinweis = e.ursprung

),
foo AS 
(
    SELECT 
        *,
        array_append(array_append(full_name, ursprung::text), hinweis::text) AS my_array
    FROM
        subordinates
    ORDER BY
        ursprung
)
SELECT
  --t_id,
    --array_length(my_array, 1),
    --my_array[1],
my_array    
    
FROM
    foo
--GROUP BY
  --  my_array[1],
*/

/*
    
SELECT 
    a.ursprung, a.hinweis
FROM
    arp_npl.rechtsvorschrften_hinweisweiteredokumente AS a
    JOIN arp_npl.rechtsvorschrften_hinweisweiteredokumente AS b 
    ON a.ursprung = b.hinweis

,
urursprung AS 
(
   SELECT 
        ursprung
    FROM
    arp_npl.rechtsvorschrften_hinweisweiteredokumente

    EXCEPT

    SELECT 
        hinweis
    FROM
        arp_npl.rechtsvorschrften_hinweisweiteredokumente 
)

SELECT
    *
FROM
    subordinates AS s
    LEFT JOIN urursprung AS u
    ON s.ursprung = u.ursprung
ORDER BY
    s.ursprung
   
*/

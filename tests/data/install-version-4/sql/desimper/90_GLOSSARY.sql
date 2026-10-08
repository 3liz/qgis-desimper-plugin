--
-- PostgreSQL database dump
--






SET statement_timeout = 0;
SET lock_timeout = 0;


SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: nomenclature_destinations; Type: TABLE DATA; Schema: desimper; Owner: -
--

INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (1, 'PLA', 'Place');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (2, 'PAJ', 'Parc et jardin');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (3, 'PAR', 'Parking');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (4, 'ECO', 'École');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (5, 'VOI', 'Voirie');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (6, 'CDO', 'Cheminement doux');
INSERT INTO desimper.nomenclature_destinations (id, code, libelle) VALUES (7, 'AUT', 'Autre');


--
-- Data for Name: nomenclature_pollution; Type: TABLE DATA; Schema: desimper; Owner: -
--

INSERT INTO desimper.nomenclature_pollution (id, code, libelle) VALUES (1, 'NON', 'Non');
INSERT INTO desimper.nomenclature_pollution (id, code, libelle) VALUES (2, 'PCH', 'Pollution chronique');
INSERT INTO desimper.nomenclature_pollution (id, code, libelle) VALUES (3, 'AUT', 'Autre type de pollution');


--
-- Data for Name: nomenclature_revetements; Type: TABLE DATA; Schema: desimper; Owner: -
--

INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (1, 'PDR', 'Pavés drainants', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (2, 'RDR', 'Revêtement drainant', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (3, 'EV', 'Espaces verts', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (4, 'SS', 'Sol souple', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (5, 'SR', 'Stabilisé renforcé', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (6, 'GR', 'Graviers', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (7, 'DA', 'Dalles alvéolaires', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (8, 'ASP', 'Autre surface perméable', true);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (9, 'EN', 'Enrobé', false);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (10, 'PND', 'Pavés non drainants', false);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (11, 'SRC', 'Stabilisé renforcé compacté', false);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (12, 'TOI', 'Toiture', false);
INSERT INTO desimper.nomenclature_revetements (id, code, libelle, impermeable) VALUES (13, 'ASI', 'Autre surface imperméable', false);


--
-- Data for Name: nomenclature_type_projet; Type: TABLE DATA; Schema: desimper; Owner: -
--

INSERT INTO desimper.nomenclature_type_projet (id, code, libelle) VALUES (1, 'REQ', 'Requalification');
INSERT INTO desimper.nomenclature_type_projet (id, code, libelle) VALUES (2, 'CRE', 'Création');


--
-- Data for Name: nomenclature_usages_surface; Type: TABLE DATA; Schema: desimper; Owner: -
--

INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (1, 'TRO', 'Trottoir');
INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (2, 'PCY', 'Piste cyclable');
INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (3, 'CEC', 'Cours d''école');
INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (4, 'PLA', 'Place');
INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (5, 'PAR', 'Parvis');
INSERT INTO desimper.nomenclature_usages_surface (id, code, libelle) VALUES (6, 'CHA', 'Chaussée');


--
-- Name: nomenclature_destinations_id_seq; Type: SEQUENCE SET; Schema: desimper; Owner: -
--

SELECT pg_catalog.setval('desimper.nomenclature_destinations_id_seq', 7, true);


--
-- Name: nomenclature_pollution_id_seq; Type: SEQUENCE SET; Schema: desimper; Owner: -
--

SELECT pg_catalog.setval('desimper.nomenclature_pollution_id_seq', 3, true);


--
-- Name: nomenclature_revetements_id_seq; Type: SEQUENCE SET; Schema: desimper; Owner: -
--

SELECT pg_catalog.setval('desimper.nomenclature_revetements_id_seq', 13, true);


--
-- Name: nomenclature_type_projet_id_seq; Type: SEQUENCE SET; Schema: desimper; Owner: -
--

SELECT pg_catalog.setval('desimper.nomenclature_type_projet_id_seq', 2, true);


--
-- Name: nomenclature_usages_surface_id_seq; Type: SEQUENCE SET; Schema: desimper; Owner: -
--

SELECT pg_catalog.setval('desimper.nomenclature_usages_surface_id_seq', 6, true);


--
-- PostgreSQL database dump complete
--




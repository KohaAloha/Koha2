-- Label Templates
LOCK TABLES `labels_templates` WRITE;
INSERT INTO `labels_templates` VALUES
(1,'Avery 5160 | 1 x 2-5/8','3 colonnes, 10 lignes d''�tiquette',8.5,11,2.625,1,0.5,0.1875,3,10,0.125,0,1,'INCH',7),
(2,'Gaylord 8511 Spine Label','Imprime uniquement dans la colnne de gauche d''une planche Gaylord 8511.',8.5,11,1,1.25,0.6,0.5,1,8,0,0,NULL,'INCH',10),
(3,'Avery 5460 vertical','',3.625,5.625,1.5,0.75,0.38,0.35,2,7,0.25,0,NULL,'INCH',8),
(4,'Avery 5460 Etiquettes de cote','',5.625,3.625,0.75,1.5,0.35,0.31,7,2,0,0.25,NULL,'INCH',8),
(5,'Avery 8163','2colonnes x 5 colonnes',8.5,11,4,2,0.5,0.17,2,5,0.2,0.01,NULL,'INCH',11),
(6,'cards','Avery 5160 | 1 x 2-5/8 : 1 x 2-5/8\"  [3x10] : equivalent: Gaylord JD-ML3000',8.5,11,2.75,1.05,0.25,0,3,10,0.2,0.01,NULL,'INCH',8);
UNLOCK TABLES; 
LOCK TABLES `labels_conf` WRITE;
/*!40000 ALTER TABLE `labels_conf` DISABLE KEYS */;
INSERT INTO `labels_conf` VALUES (5,'CODE39',2,3,0,0,0,0,4,1,0,0,1,'BIBBAR','biblio and barcode',1,NULL,NULL,0),(6,'CODE39',2,0,0,0,3,4,0,1,0,3,1,'BAR','alternating',1,1,NULL,0);
/*!40000 ALTER TABLE `labels_conf` ENABLE KEYS */;
UNLOCK TABLES;

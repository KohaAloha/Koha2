-- availability statuses
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('ITEMLOST','0','');
INSERT INTO `authorised_values`  (category, authorised_value, lib) VALUES ('ITEMLOST','2','Long Overdue (Lost)');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('ITEMLOST','1','Lost');
INSERT INTO `authorised_values`  (category, authorised_value, lib ) VALUES ('ITEMLOST','3','Lost and Paid For');
INSERT INTO `authorised_values`  (category, authorised_value, lib )VALUES ('ITEMLOST','4','Missing in Inventory');

-- damaged status of an item
INSERT INTO `authorised_values`  (category, authorised_value, lib) VALUES ('DAMAGED','0','');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('DAMAGED','1','Damaged');

-- location qualification for an item, departments are linked by default to items.location
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','0','');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','1','Reference');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','2','Fiction');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','3','Biography');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','4','Media');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('SHELF_LOC','4','New Book Shelf');

-- location qualification for an item, linked to items.stack
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('STACK','0','');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('STACK','1','Special Collection');

-- loanability status of an item, linked to items.notforloan
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('NOTFORLOAN','-1','Ordered');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('NOTFORLOAN','0','');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('NOTFORLOAN','1','Not For Loan');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('NOTFORLOAN','2','Staff Collection');

-- restricted status of an item, linked to items.restricted
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('RESTRICTED','0','');
INSERT INTO `authorised_values` (category, authorised_value, lib) VALUES ('RESTRICTED','1','Restricted Access');

CREATE TABLE IF NOT EXISTS `ba_restaurants` (
  `id` varchar(64) NOT NULL,
  `label` varchar(128) NOT NULL,
  `job` varchar(64) NOT NULL,
  `society_account` varchar(128) DEFAULT NULL,
  `theme_json` longtext DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_points` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `point_type` varchar(32) NOT NULL,
  `label` varchar(128) DEFAULT NULL,
  `x` double NOT NULL,
  `y` double NOT NULL,
  `z` double NOT NULL,
  `heading` double NOT NULL DEFAULT 0,
  `prop_model` varchar(96) DEFAULT NULL,
  `screen_size` varchar(32) DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`),
  KEY `point_type` (`point_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_categories` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `name` varchar(64) NOT NULL,
  `label` varchar(128) NOT NULL,
  `icon` varchar(16) DEFAULT NULL,
  `image` varchar(512) DEFAULT NULL,
  `sort_order` int(11) NOT NULL DEFAULT 1,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`),
  UNIQUE KEY `restaurant_category_name` (`restaurant_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_products` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `category` varchar(64) NOT NULL,
  `label` varchar(128) NOT NULL,
  `description` text DEFAULT NULL,
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `item_name` varchar(128) DEFAULT NULL,
  `image` varchar(512) DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`),
  KEY `category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_menus` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `label` varchar(128) NOT NULL,
  `description` text DEFAULT NULL,
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `products_json` longtext NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_orders` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `order_number` int(11) NOT NULL,
  `customer_identifier` varchar(128) DEFAULT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `payment_method` varchar(32) NOT NULL DEFAULT 'card',
  `payment_status` varchar(32) NOT NULL DEFAULT 'pending',
  `subtotal` decimal(10,2) NOT NULL DEFAULT 0.00,
  `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `total` decimal(10,2) NOT NULL DEFAULT 0.00,
  `items_json` longtext NOT NULL,
  `cashier_identifier` varchar(128) DEFAULT NULL,
  `cashier_name` varchar(128) DEFAULT NULL,
  `paid_at` timestamp NULL DEFAULT NULL,
  `cash_closed_at` timestamp NULL DEFAULT NULL,
  `cash_closed_by` varchar(128) DEFAULT NULL,
  `cash_closed_by_name` varchar(128) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`),
  KEY `order_number` (`order_number`),
  KEY `status` (`status`),
  KEY `payment_status` (`payment_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ba_restaurant_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `restaurant_id` varchar(64) NOT NULL,
  `order_id` int(11) DEFAULT NULL,
  `order_number` int(11) DEFAULT NULL,
  `method` varchar(32) NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'booked',
  `amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `society_account` varchar(128) DEFAULT NULL,
  `cashier_identifier` varchar(128) DEFAULT NULL,
  `cashier_name` varchar(128) DEFAULT NULL,
  `booked_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `restaurant_id` (`restaurant_id`),
  KEY `order_id` (`order_id`),
  KEY `method` (`method`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `ba_restaurant_categories` ADD COLUMN IF NOT EXISTS `image` varchar(512) DEFAULT NULL;
ALTER TABLE `ba_restaurant_points` ADD COLUMN IF NOT EXISTS `prop_model` varchar(96) DEFAULT NULL;
ALTER TABLE `ba_restaurant_points` ADD COLUMN IF NOT EXISTS `screen_size` varchar(32) DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `cashier_identifier` varchar(128) DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `cashier_name` varchar(128) DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `subtotal` decimal(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `paid_at` timestamp NULL DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `cash_closed_at` timestamp NULL DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `cash_closed_by` varchar(128) DEFAULT NULL;
ALTER TABLE `ba_restaurant_orders` ADD COLUMN IF NOT EXISTS `cash_closed_by_name` varchar(128) DEFAULT NULL;
ALTER TABLE `ba_restaurant_payments` ADD COLUMN IF NOT EXISTS `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00;

INSERT INTO `ba_restaurants` (`id`, `label`, `job`, `society_account`, `theme_json`, `enabled`) VALUES
('burgershot', 'Burger Shot', 'burgershot', 'society_burgershot', '{"primary":"#ff6a3d","accent":"#31d3c5","background":"#151018"}', 1),
('johnnys_diner', 'Johnnys Diner', 'johnnys_diner', 'society_johnnys_diner', '{"primary":"#d84f45","accent":"#f4c542","background":"#12202a"}', 1)
ON DUPLICATE KEY UPDATE label = VALUES(label), job = VALUES(job), society_account = VALUES(society_account), theme_json = VALUES(theme_json);

INSERT INTO `ba_restaurant_categories` (`restaurant_id`, `name`, `label`, `icon`, `image`, `sort_order`, `enabled`) VALUES
('burgershot', 'burger', 'Burger', 'B', '', 1, 1),
('burgershot', 'drinks', 'Getraenke', 'D', '', 2, 1),
('johnnys_diner', 'mains', 'Speisen', 'S', '', 1, 1),
('johnnys_diner', 'drinks', 'Getraenke', 'D', '', 2, 1)
ON DUPLICATE KEY UPDATE label = VALUES(label), icon = VALUES(icon), sort_order = VALUES(sort_order), enabled = VALUES(enabled);

INSERT INTO `ba_restaurant_products` (`restaurant_id`, `category`, `label`, `description`, `price`, `item_name`, `image`, `enabled`) VALUES
('burgershot', 'burger', 'Classic Burger', '', 12.50, 'burger', 'nui://ox_inventory/web/images/burger.png', 1),
('burgershot', 'drinks', 'Cola', '', 4.00, 'cola', 'nui://ox_inventory/web/images/cola.png', 1),
('johnnys_diner', 'mains', 'Diner Sandwich', '', 10.50, 'sandwich', 'nui://ox_inventory/web/images/sandwich.png', 1),
('johnnys_diner', 'drinks', 'Kaffee', '', 3.50, 'coffee', 'nui://ox_inventory/web/images/coffee.png', 1);

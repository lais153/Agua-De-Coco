CREATE TABLE `audit` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`created` text NOT NULL,
	`action` text NOT NULL,
	`details` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `closings` (
	`owner` text NOT NULL,
	`day` text NOT NULL,
	`created` text NOT NULL,
	`snapshot` text NOT NULL,
	PRIMARY KEY(`owner`, `day`)
);
--> statement-breakpoint
CREATE TABLE `products` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`name` text NOT NULL,
	`price` integer NOT NULL,
	`active` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `sales` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`day` text NOT NULL,
	`created` text NOT NULL,
	`payment` text NOT NULL,
	`items` text NOT NULL,
	`total` integer NOT NULL,
	`deleted` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL
);

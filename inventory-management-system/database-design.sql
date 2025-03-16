- สร้างฐานข้อมูลระบบจัดการสินค้าคงคลังรองรับการนำเข้าเป็น Lots
CREATE DATABASE inventory_management;
USE inventory_management;

-- ตารางหมวดหมู่สินค้า (Product Categories)
CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ตารางผู้จัดจำหน่าย (Suppliers)
CREATE TABLE suppliers (
    supplier_id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_name VARCHAR(100),
    contact_phone VARCHAR(20),
    contact_email VARCHAR(100),
    address TEXT,
    city VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50),
    tax_id VARCHAR(50),
    status ENUM('active', 'inactive') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ตารางสินค้า (Products)
CREATE TABLE products (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_code VARCHAR(50) UNIQUE NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    description TEXT,
    category_id INT,
    unit_of_measure VARCHAR(20) NOT NULL,
    cost_price DECIMAL(10, 2),
    selling_price DECIMAL(10, 2) NOT NULL,
    reorder_level INT NOT NULL,
    target_stock_level INT NOT NULL,
    barcode VARCHAR(100),
    image_url VARCHAR(255),
    supplier_id INT,
    lot_control BOOLEAN DEFAULT FALSE, -- เพิ่มฟิลด์สำหรับระบุว่าสินค้าต้องควบคุมเป็น lot หรือไม่
    expiry_control BOOLEAN DEFAULT FALSE, -- เพิ่มฟิลด์สำหรับระบุว่าสินค้าต้องควบคุมวันหมดอายุหรือไม่
    status ENUM('active', 'inactive', 'discontinued') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES categories(category_id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

-- ตารางคลังสินค้า (Warehouses)
CREATE TABLE warehouses (
    warehouse_id INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,
    location VARCHAR(100),
    address TEXT,
    manager_name VARCHAR(100),
    contact_phone VARCHAR(20),
    contact_email VARCHAR(100),
    status ENUM('active', 'inactive') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ตารางสถานที่เก็บสินค้าในคลัง (Locations within warehouses)
CREATE TABLE storage_locations (
    location_id INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_id INT NOT NULL,
    location_code VARCHAR(50) NOT NULL,
    description VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตาราง Lots (สร้างขึ้นใหม่)
CREATE TABLE lots (
    lot_id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    lot_number VARCHAR(100) NOT NULL,
    manufacture_date DATE,
    expiry_date DATE,
    supplier_id INT,
    receipt_id INT, -- อ้างอิงไปยังการรับสินค้า
    po_id INT, -- อ้างอิงไปยังใบสั่งซื้อ
    unit_cost DECIMAL(10, 2), -- ต้นทุนต่อหน่วยของสินค้าใน lot นี้
    notes TEXT,
    status ENUM('active', 'inactive', 'expired', 'quarantine', 'consumed') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
    UNIQUE KEY (product_id, lot_number) -- สินค้าและเลข lot ต้องไม่ซ้ำกัน
);

-- ตารางสต็อกสินค้า (Inventory) ปรับให้รองรับ lots
CREATE TABLE inventory (
    inventory_id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    warehouse_id INT NOT NULL,
    location_id INT,
    quantity INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id),
    UNIQUE KEY product_lot_warehouse_location (product_id, lot_id, warehouse_id, location_id) -- ปรับ unique key ให้รวม lot_id
);

-- ตารางการเคลื่อนไหวของสินค้า (Inventory Movements) ปรับให้รองรับ lots
CREATE TABLE inventory_movements (
    movement_id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    warehouse_id INT NOT NULL,
    location_id INT,
    reference_id VARCHAR(100),
    reference_type ENUM('purchase', 'sale', 'transfer', 'adjustment', 'return', 'production', 'consumption') NOT NULL,
    quantity_change INT NOT NULL,
    movement_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    unit_cost DECIMAL(10, 2), -- ต้นทุนต่อหน่วยของการเคลื่อนไหวนี้
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id)
);

-- ตารางคำสั่งซื้อ (Purchase Orders)
CREATE TABLE purchase_orders (
    po_id INT AUTO_INCREMENT PRIMARY KEY,
    po_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id INT NOT NULL,
    order_date DATE NOT NULL,
    expected_delivery_date DATE,
    status ENUM('draft', 'submitted', 'approved', 'received', 'partially_received', 'cancelled') DEFAULT 'draft',
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    warehouse_id INT NOT NULL,
    notes TEXT,
    created_by INT,
    approved_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการสินค้าในคำสั่งซื้อ (Purchase Order Items)
CREATE TABLE purchase_order_items (
    po_item_id INT AUTO_INCREMENT PRIMARY KEY,
    po_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    line_total DECIMAL(12, 2) NOT NULL,
    received_quantity INT DEFAULT 0,
    requires_lot BOOLEAN DEFAULT FALSE, -- เพิ่มฟิลด์สำหรับระบุว่าต้องรับเป็น lot หรือไม่
    FOREIGN KEY (po_id) REFERENCES purchase_orders(po_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ตารางการรับสินค้า (Goods Receipts)
CREATE TABLE goods_receipts (
    receipt_id INT AUTO_INCREMENT PRIMARY KEY,
    receipt_number VARCHAR(50) UNIQUE NOT NULL,
    po_id INT,
    supplier_id INT NOT NULL,
    receipt_date DATE NOT NULL,
    warehouse_id INT NOT NULL,
    status ENUM('pending', 'completed', 'returned') DEFAULT 'pending',
    notes TEXT,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (po_id) REFERENCES purchase_orders(po_id),
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการรับสินค้า (Goods Receipt Items) ปรับให้รองรับ lots
CREATE TABLE goods_receipt_items (
    receipt_item_id INT AUTO_INCREMENT PRIMARY KEY,
    receipt_id INT NOT NULL,
    product_id INT NOT NULL,
    po_item_id INT,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    location_id INT,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    batch_number VARCHAR(50), -- สำหรับความเข้ากันได้กับระบบเดิม ใช้ lot_id แทน
    expiry_date DATE,
    notes TEXT,
    FOREIGN KEY (receipt_id) REFERENCES goods_receipts(receipt_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (po_item_id) REFERENCES purchase_order_items(po_item_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id)
);

-- ตารางใบเบิกสินค้า (Stock Requisitions)
CREATE TABLE stock_requisitions (
    requisition_id INT AUTO_INCREMENT PRIMARY KEY,
    requisition_number VARCHAR(50) UNIQUE NOT NULL,
    requested_by INT,
    department VARCHAR(100),
    request_date DATE NOT NULL,
    required_date DATE,
    status ENUM('pending', 'approved', 'issued', 'partially_issued', 'cancelled') DEFAULT 'pending',
    notes TEXT,
    warehouse_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการเบิกสินค้า (Stock Requisition Items)
CREATE TABLE stock_requisition_items (
    requisition_item_id INT AUTO_INCREMENT PRIMARY KEY,
    requisition_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity_requested INT NOT NULL,
    quantity_issued INT DEFAULT 0,
    notes TEXT,
    FOREIGN KEY (requisition_id) REFERENCES stock_requisitions(requisition_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ตารางการเบิกจ่ายสินค้า (Issue Items) สร้างใหม่เพื่อบันทึกการเบิกจ่ายที่มาจาก lot ไหนบ้าง
CREATE TABLE issue_items (
    issue_id INT AUTO_INCREMENT PRIMARY KEY,
    requisition_item_id INT NOT NULL,
    product_id INT NOT NULL,
    lot_id INT, -- อ้างอิงไปยัง lot ที่จ่ายออกไป
    warehouse_id INT NOT NULL,
    location_id INT,
    quantity INT NOT NULL,
    issue_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    issued_by INT,
    notes TEXT,
    FOREIGN KEY (requisition_item_id) REFERENCES stock_requisition_items(requisition_item_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id)
);

-- ตารางรายการปรับสต็อกสินค้า (Stock Adjustments)
CREATE TABLE stock_adjustments (
    adjustment_id INT AUTO_INCREMENT PRIMARY KEY,
    adjustment_number VARCHAR(50) UNIQUE NOT NULL,
    warehouse_id INT NOT NULL,
    adjustment_date DATE NOT NULL,
    adjustment_type ENUM('increase', 'decrease') NOT NULL,
    reason VARCHAR(100) NOT NULL,
    notes TEXT,
    status ENUM('draft', 'approved', 'completed') DEFAULT 'draft',
    created_by INT,
    approved_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการสินค้าที่ปรับสต็อก (Stock Adjustment Items) ปรับให้รองรับ lots
CREATE TABLE stock_adjustment_items (
    adjustment_item_id INT AUTO_INCREMENT PRIMARY KEY,
    adjustment_id INT NOT NULL,
    product_id INT NOT NULL,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    location_id INT,
    quantity INT NOT NULL,
    notes TEXT,
    FOREIGN KEY (adjustment_id) REFERENCES stock_adjustments(adjustment_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id)
);

-- ตารางการโอนย้ายสินค้าระหว่างคลัง (Stock Transfers)
CREATE TABLE stock_transfers (
    transfer_id INT AUTO_INCREMENT PRIMARY KEY,
    transfer_number VARCHAR(50) UNIQUE NOT NULL,
    source_warehouse_id INT NOT NULL,
    destination_warehouse_id INT NOT NULL,
    transfer_date DATE NOT NULL,
    status ENUM('draft', 'in_transit', 'completed', 'cancelled') DEFAULT 'draft',
    notes TEXT,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (source_warehouse_id) REFERENCES warehouses(warehouse_id),
    FOREIGN KEY (destination_warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการสินค้าที่โอนย้าย (Stock Transfer Items) ปรับให้รองรับ lots
CREATE TABLE stock_transfer_items (
    transfer_item_id INT AUTO_INCREMENT PRIMARY KEY,
    transfer_id INT NOT NULL,
    product_id INT NOT NULL,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    source_location_id INT,
    destination_location_id INT,
    quantity INT NOT NULL,
    notes TEXT,
    FOREIGN KEY (transfer_id) REFERENCES stock_transfers(transfer_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (source_location_id) REFERENCES storage_locations(location_id),
    FOREIGN KEY (destination_location_id) REFERENCES storage_locations(location_id)
);

-- ตารางผู้ใช้งาน (Users)
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    role ENUM('admin', 'manager', 'staff', 'viewer') NOT NULL,
    status ENUM('active', 'inactive') DEFAULT 'active',
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ตารางการตรวจนับสินค้า (Inventory Count)
CREATE TABLE inventory_counts (
    count_id INT AUTO_INCREMENT PRIMARY KEY,
    count_number VARCHAR(50) UNIQUE NOT NULL,
    warehouse_id INT NOT NULL,
    count_date DATE NOT NULL,
    status ENUM('planned', 'in_progress', 'completed', 'cancelled') DEFAULT 'planned',
    count_type ENUM('full', 'partial', 'cycle') NOT NULL,
    notes TEXT,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ตารางรายการนับสินค้า (Inventory Count Items) ปรับให้รองรับ lots
CREATE TABLE inventory_count_items (
    count_item_id INT AUTO_INCREMENT PRIMARY KEY,
    count_id INT NOT NULL,
    product_id INT NOT NULL,
    lot_id INT, -- เพิ่มฟิลด์อ้างอิงไปยัง lot
    location_id INT,
    expected_quantity INT NOT NULL,
    counted_quantity INT,
    status ENUM('pending', 'counted', 'verified', 'adjusted') DEFAULT 'pending',
    notes TEXT,
    counted_by INT,
    counted_at TIMESTAMP,
    FOREIGN KEY (count_id) REFERENCES inventory_counts(count_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (location_id) REFERENCES storage_locations(location_id)
);

-- ตารางติดตามวันหมดอายุของสินค้า (Expiry Tracking) สร้างใหม่
CREATE TABLE expiry_tracking (
    tracking_id INT AUTO_INCREMENT PRIMARY KEY,
    lot_id INT NOT NULL,
    product_id INT NOT NULL,
    expiry_date DATE NOT NULL,
    alert_threshold_days INT DEFAULT 90, -- จำนวนวันก่อนหมดอายุที่ต้องการแจ้งเตือน
    alert_sent BOOLEAN DEFAULT FALSE,
    status ENUM('active', 'expired', 'removed') DEFAULT 'active',
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ตารางคุณภาพสินค้า (Quality Control) สร้างใหม่
CREATE TABLE quality_control (
    qc_id INT AUTO_INCREMENT PRIMARY KEY,
    lot_id INT NOT NULL,
    product_id INT NOT NULL,
    inspection_date DATE NOT NULL,
    inspector_id INT,
    status ENUM('pending', 'approved', 'rejected', 'quarantine') DEFAULT 'pending',
    test_results TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ตารางราคาต้นทุนตามล็อต (FIFO Cost Tracking) สร้างใหม่
CREATE TABLE lot_costs (
    cost_id INT AUTO_INCREMENT PRIMARY KEY,
    lot_id INT NOT NULL,
    product_id INT NOT NULL,
    unit_cost DECIMAL(10, 2) NOT NULL,
    quantity_received INT NOT NULL,
    quantity_remaining INT NOT NULL,
    receipt_date DATE NOT NULL,
    receipt_id INT,
    po_id INT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (lot_id) REFERENCES lots(lot_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);
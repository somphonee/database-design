
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

-- สร้าง View สำหรับดูสินค้าที่อยู่ในจุดสั่งซื้อ
CREATE VIEW products_to_reorder AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    p.reorder_level,
    p.target_stock_level,
    COALESCE(SUM(i.quantity), 0) AS current_stock,
    p.target_stock_level - COALESCE(SUM(i.quantity), 0) AS recommended_order_quantity,
    s.supplier_name,
    s.supplier_id
FROM 
    products p
LEFT JOIN 
    inventory i ON p.product_id = i.product_id
LEFT JOIN 
    suppliers s ON p.supplier_id = s.supplier_id
GROUP BY 
    p.product_id,
    p.product_code,
    p.product_name,
    p.reorder_level,
    p.target_stock_level,
    s.supplier_name,
    s.supplier_id
HAVING 
    COALESCE(SUM(i.quantity), 0) <= p.reorder_level;

-- สร้าง View สำหรับดูสินค้าตามล็อต
CREATE VIEW inventory_by_lot AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    l.lot_id,
    l.lot_number,
    l.manufacture_date,
    l.expiry_date,
    w.warehouse_id,
    w.warehouse_name,
    sl.location_id,
    sl.location_code,
    i.quantity,
    l.unit_cost,
    (l.unit_cost * i.quantity) AS total_cost,
    CASE 
        WHEN l.expiry_date IS NOT NULL THEN 
            DATEDIFF(l.expiry_date, CURDATE())
        ELSE NULL
    END AS days_to_expiry
FROM 
    inventory i
JOIN 
    products p ON i.product_id = p.product_id
JOIN 
    lots l ON i.lot_id = l.lot_id
JOIN 
    warehouses w ON i.warehouse_id = w.warehouse_id
LEFT JOIN 
    storage_locations sl ON i.location_id = sl.location_id
WHERE 
    i.quantity > 0;

-- สร้าง View สำหรับดูสินค้าที่ใกล้หมดอายุ
CREATE VIEW expiring_inventory AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    l.lot_id,
    l.lot_number,
    l.expiry_date,
    DATEDIFF(l.expiry_date, CURDATE()) AS days_to_expiry,
    SUM(i.quantity) AS total_quantity,
    w.warehouse_name
FROM 
    inventory i
JOIN 
    products p ON i.product_id = p.product_id
JOIN 
    lots l ON i.lot_id = l.lot_id
JOIN 
    warehouses w ON i.warehouse_id = w.warehouse_id
WHERE 
    l.expiry_date IS NOT NULL
    AND l.expiry_date >= CURDATE()
    AND i.quantity > 0
GROUP BY 
    p.product_id,
    p.product_code,
    p.product_name,
    l.lot_id,
    l.lot_number,
    l.expiry_date,
    w.warehouse_name
HAVING 
    DATEDIFF(l.expiry_date, CURDATE()) <= 90
ORDER BY 
    days_to_expiry ASC;

-- สร้าง View สำหรับการใช้สินค้าตามหลัก FIFO (First In First Out)
CREATE VIEW fifo_recommendation AS
SELECT 
    p.product_id,
    p.product_code,
    p.product_name,
    l.lot_id,
    l.lot_number,
    l.manufacture_date,
    l.expiry_date,
    w.warehouse_id,
    w.warehouse_name,
    sl.location_code,
    i.quantity,
    ROW_NUMBER() OVER (
        PARTITION BY p.product_id, w.warehouse_id
        ORDER BY 
            CASE WHEN l.expiry_date IS NULL THEN 1 ELSE 0 END, -- จัดลำดับสินค้าที่มีวันหมดอายุก่อน
            l.expiry_date ASC, -- จัดลำดับตามวันหมดอายุใกล้สุดก่อน
            l.manufacture_date ASC, -- จัดลำดับตามวันผลิตเก่าสุดก่อน
            l.lot_id ASC -- จัดลำดับตามล็อตเก่าสุดก่อน
    ) AS fifo_rank
FROM 
    inventory i
JOIN 
    products p ON i.product_id = p.product_id
JOIN 
    lots l ON i.lot_id = l.lot_id
JOIN 
    warehouses w ON i.warehouse_id = w.warehouse_id
LEFT JOIN 
    storage_locations sl ON i.location_id = sl.location_id
WHERE 
    i.quantity > 0
ORDER BY 
    p.product_id,
    w.warehouse_id,
    fifo_rank;

-- สร้าง TRIGGER สำหรับอัพเดทสถานะล็อตเมื่อใกล้หมดอายุ
DELIMITER //
CREATE TRIGGER update_lot_status_on_expiry
BEFORE UPDATE ON lots
FOR EACH ROW
BEGIN
    IF NEW.expiry_date IS NOT NULL AND NEW.expiry_date < CURDATE() AND NEW.status != 'expired' THEN
        SET NEW.status = 'expired';
    END IF;
END //
DELIMITER ;

-- สร้าง TRIGGER สำหรับตรวจสอบการเพิ่มสินค้าในสต็อกว่าเป็นสินค้าที่ต้องการควบคุมล็อตหรือไม่
DELIMITER //
CREATE TRIGGER check_lot_control_on_insert
BEFORE INSERT ON inventory
FOR EACH ROW
BEGIN
    DECLARE requires_lot BOOLEAN;
    
    SELECT lot_control INTO requires_lot
    FROM products
    WHERE product_id = NEW.product_id;
    
    IF requires_lot = TRUE AND NEW.lot_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This product requires lot control. Lot ID cannot be NULL.';
    END IF;
END //
DELIMITER ;


-- สร้าง TRIGGER สำหรับอัพเดทจำนวนสินค้าคงเหลือในล็อต (lot_costs table) เมื่อมีการเคลื่อนไหว
DELIMITER //
CREATE TRIGGER update_lot_quantity_remaining
AFTER INSERT ON inventory_movements
FOR EACH ROW
BEGIN
    IF NEW.lot_id IS NOT NULL THEN
        IF NEW.quantity_change < 0 THEN
            -- ถ้าเป็นการเบิกจ่ายออก ให้ลดจำนวนคงเหลือในล็อต
            UPDATE lot_costs
            SET quantity_remaining = quantity_remaining + NEW.quantity_change
            WHERE lot_id = NEW.lot_id;
        END IF;
    END IF;
END //
DELIMITER ;


-- สร้าง PROCEDURE สำหรับคำนวณต้นทุนสินค้าแบบ FIFO เมื่อมีการเบิกจ่าย 
DELIMITER //
CREATE PROCEDURE calculate_fifo_cost(
    IN p_product_id INT,
    IN p_quantity INT,
    OUT p_total_cost DECIMAL(12, 2)
)
BEGIN
    DECLARE v_remaining INT;
    DECLARE v_lot_id INT;
    DECLARE v_unit_cost DECIMAL(10, 2);
    DECLARE v_available INT;
    DECLARE v_cost_for_lot DECIMAL(12, 2);
    DECLARE v_total_calculated DECIMAL(12, 2) DEFAULT 0;
    DECLARE v_quantity_to_calculate INT;
    DECLARE done INT DEFAULT FALSE;

    DECLARE lot_cursor CURSOR FOR
        SELECT l.lot_id, lc.unit_cost, lc.quantity_remaining
        FROM lot_costs lc
        JOIN lots l ON lc.lot_id = l.lot_id
        WHERE lc.product_id = p_product_id
        AND lc.quantity_remaining > 0
        ORDER BY 
            CASE WHEN l.expiry_date IS NULL THEN 1 ELSE 0 END,
            l.expiry_date ASC,
            l.manufacture_date ASC,
            lc.receipt_date ASC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    SET v_remaining = p_quantity;
    SET p_total_cost = 0;

    OPEN lot_cursor;
    
    calculate_loop: LOOP
        FETCH lot_cursor INTO v_lot_id, v_unit_cost, v_available;
        
        IF done OR v_remaining <= 0 THEN
            LEAVE calculate_loop;
        END IF;
        
        IF v_available >= v_remaining THEN
            -- หากล็อตนี้มีเพียงพอสำหรับความต้องการที่เหลือทั้งหมด
            SET v_cost_for_lot = v_remaining * v_unit_cost;
            SET v_total_calculated = v_total_calculated + v_cost_for_lot;
            SET v_remaining = 0;
        ELSE
            -- หากล็อตนี้ไม่เพียงพอ ใช้ทั้งหมดที่มีแล้วไปล็อตถัดไป
            SET v_cost_for_lot = v_available * v_unit_cost;
            SET v_total_calculated = v_total_calculated + v_cost_for_lot;
            SET v_remaining = v_remaining - v_available;
        END IF;
    END LOOP;

    CLOSE lot_cursor;

    -- ถ้ายังเหลือความต้องการที่ไม่ได้คำนวณ (กรณีสต็อกไม่เพียงพอ)
    IF v_remaining > 0 THEN
        -- ใช้ต้นทุนเฉลี่ยของสินค้านั้นหรือราคาล่าสุด
        SELECT COALESCE(AVG(unit_cost), 0) INTO v_unit_cost
        FROM lot_costs
        WHERE product_id = p_product_id;
        
        SET v_cost_for_lot = v_remaining * v_unit_cost;
        SET v_total_calculated = v_total_calculated + v_cost_for_lot;
    END IF;

    SET p_total_cost = v_total_calculated;
END //
DELIMITER ;

-- สร้าง PROCEDURE สำหรับการเบิกจ่ายสินค้าตามหลัก FIFO
DELIMITER //
CREATE PROCEDURE issue_inventory_fifo(
    IN p_product_id INT,
    IN p_warehouse_id INT,
    IN p_quantity INT,
    IN p_reference_id VARCHAR(100),
    IN p_reference_type VARCHAR(50),
    IN p_created_by INT,
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_remaining INT;
    DECLARE v_lot_id INT;
    DECLARE v_location_id INT;
    DECLARE v_available INT;
    DECLARE v_unit_cost DECIMAL(10, 2);
    DECLARE v_to_issue INT;
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_total_issued INT DEFAULT 0;
    
    DECLARE lot_cursor CURSOR FOR
        SELECT i.lot_id, i.location_id, i.quantity, l.unit_cost
        FROM inventory i
        JOIN lots l ON i.lot_id = l.lot_id
        WHERE i.product_id = p_product_id
        AND i.warehouse_id = p_warehouse_id
        AND i.quantity > 0
        ORDER BY 
            CASE WHEN l.expiry_date IS NULL THEN 1 ELSE 0 END,
            l.expiry_date ASC,
            l.manufacture_date ASC,
            l.lot_id ASC;
            
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- ตรวจสอบว่ามีสินค้าเพียงพอหรือไม่
    SELECT SUM(quantity) INTO v_available
    FROM inventory
    WHERE product_id = p_product_id
    AND warehouse_id = p_warehouse_id;
    
    IF v_available < p_quantity THEN
        SET p_success = FALSE;
        SET p_message = CONCAT('ไม่มีสินค้าเพียงพอ มีอยู่เพียง ', v_available, ' หน่วย');
        LEAVE issue_inventory_fifo;
    END IF;
    
    START TRANSACTION;
    
    SET v_remaining = p_quantity;
    
    OPEN lot_cursor;
    
    issue_loop: LOOP
        FETCH lot_cursor INTO v_lot_id, v_location_id, v_available, v_unit_cost;
        
        IF done OR v_remaining <= 0 THEN
            LEAVE issue_loop;
        END IF;
        
        IF v_available >= v_remaining THEN
            -- หากล็อตนี้มีเพียงพอสำหรับความต้องการที่เหลือทั้งหมด
            SET v_to_issue = v_remaining;
        ELSE
            -- หากล็อตนี้ไม่เพียงพอ ใช้ทั้งหมดที่มีแล้วไปล็อตถัดไป
            SET v_to_issue = v_available;
        END IF;
        
        -- ปรับปรุงสต็อก
        UPDATE inventory
        SET quantity = quantity - v_to_issue
        WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND lot_id = v_lot_id
        AND location_id = v_location_id;
        
        -- บันทึกการเคลื่อนไหวสินค้า
        INSERT INTO inventory_movements (
            product_id,
            lot_id,
            warehouse_id,
            location_id,
            reference_id,
            reference_type,
            quantity_change,
            unit_cost,
            created_by
        ) VALUES (
            p_product_id,
            v_lot_id,
            p_warehouse_id,
            v_location_id,
            p_reference_id,
            p_reference_type,
            -v_to_issue,
            v_unit_cost,
            p_created_by
        );
        
        -- ปรับปรุงจำนวนคงเหลือในล็อต
        UPDATE lot_costs
        SET quantity_remaining = quantity_remaining - v_to_issue
        WHERE lot_id = v_lot_id
        AND product_id = p_product_id;
        
        SET v_remaining = v_remaining - v_to_issue;
        SET v_total_issued = v_total_issued + v_to_issue;
    END LOOP;
    
    CLOSE lot_cursor;
    
    COMMIT;
    
    SET p_success = TRUE;
    SET p_message = CONCAT('เบิกจ่ายสินค้า ', v_total_issued, ' หน่วยสำเร็จ');
END //
DELIMITER ;

-- สร้าง PROCEDURE สำหรับการรับสินค้าใหม่และสร้างล็อต
DELIMITER //
CREATE PROCEDURE receive_inventory_with_lot(
    IN p_product_id INT,
    IN p_warehouse_id INT,
    IN p_location_id INT,
    IN p_quantity INT,
    IN p_lot_number VARCHAR(100),
    IN p_manufacture_date DATE,
    IN p_expiry_date DATE,
    IN p_unit_cost DECIMAL(10, 2),
    IN p_supplier_id INT,
    IN p_receipt_id INT,
    IN p_po_id INT,
    IN p_reference_id VARCHAR(100),
    IN p_reference_type VARCHAR(50),
    IN p_created_by INT,
    OUT p_lot_id INT,
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_requires_lot BOOLEAN;
    DECLARE v_product_name VARCHAR(100);
    
    -- ตรวจสอบว่าสินค้านี้ต้องควบคุมล็อตหรือไม่
    SELECT lot_control, product_name INTO v_requires_lot, v_product_name
    FROM products
    WHERE product_id = p_product_id;
    
    START TRANSACTION;
    
    -- ตรวจสอบว่าล็อตนี้มีอยู่แล้วหรือไม่
    SELECT lot_id INTO p_lot_id
    FROM lots
    WHERE product_id = p_product_id AND lot_number = p_lot_number;
    
    IF p_lot_id IS NULL THEN
        -- สร้างล็อตใหม่
        INSERT INTO lots (
            product_id,
            lot_number,
            manufacture_date,
            expiry_date,
            supplier_id,
            receipt_id,
            po_id,
            unit_cost,
            status
        ) VALUES (
            p_product_id,
            p_lot_number,
            p_manufacture_date,
            p_expiry_date,
            p_supplier_id,
            p_receipt_id,
            p_po_id,
            p_unit_cost,
            'active'
        );
        
        SET p_lot_id = LAST_INSERT_ID();
        
        -- บันทึกข้อมูลต้นทุนล็อต
        INSERT INTO lot_costs (
            lot_id,
            product_id,
            unit_cost,
            quantity_received,
            quantity_remaining,
            receipt_date,
            receipt_id,
            po_id
        ) VALUES (
            p_lot_id,
            p_product_id,
            p_unit_cost,
            p_quantity,
            p_quantity,
            CURDATE(),
            p_receipt_id,
            p_po_id
        );
        
        -- สร้างการติดตามวันหมดอายุถ้ามีวันหมดอายุ
        IF p_expiry_date IS NOT NULL THEN
            INSERT INTO expiry_tracking (
                lot_id,
                product_id,
                expiry_date
            ) VALUES (
                p_lot_id,
                p_product_id,
                p_expiry_date
            );
        END IF;
    ELSE
        -- อัพเดทข้อมูลล็อต
        UPDATE lots
        SET 
            manufacture_date = COALESCE(p_manufacture_date, manufacture_date),
            expiry_date = COALESCE(p_expiry_date, expiry_date),
            unit_cost = CASE
                WHEN unit_cost IS NULL THEN p_unit_cost
                ELSE (unit_cost + p_unit_cost) / 2  -- คำนวณค่าเฉลี่ย
            END
        WHERE lot_id = p_lot_id;
        
        -- อัพเดทหรือเพิ่มข้อมูลต้นทุนล็อต
        INSERT INTO lot_costs (
            lot_id,
            product_id,
            unit_cost,
            quantity_received,
            quantity_remaining,
            receipt_date,
            receipt_id,
            po_id
        ) VALUES (
            p_lot_id,
            p_product_id,
            p_unit_cost,
            p_quantity,
            p_quantity,
            CURDATE(),
            p_receipt_id,
            p_po_id
        );
    END IF;
    
    -- ตรวจสอบว่ามีสินค้าในคลังและตำแหน่งนี้อยู่แล้วหรือไม่
    SET @inventory_id = NULL;
    SELECT inventory_id INTO @inventory_id
    FROM inventory
    WHERE product_id = p_product_id
    AND warehouse_id = p_warehouse_id
    AND location_id = p_location_id
    AND lot_id = p_lot_id;
    
    IF @inventory_id IS NULL THEN
        -- เพิ่มสินค้าใหม่เข้าคลัง
        INSERT INTO inventory (
            product_id,
            lot_id,
            warehouse_id,
            location_id,
            quantity
        ) VALUES (
            p_product_id,
            p_lot_id,
            p_warehouse_id,
            p_location_id,
            p_quantity
        );
    ELSE
        -- อัพเดทจำนวนสินค้าในคลัง
        UPDATE inventory
        SET quantity = quantity + p_quantity
        WHERE inventory_id = @inventory_id;
    END IF;
    
    -- บันทึกการเคลื่อนไหวสินค้า
    INSERT INTO inventory_movements (
        product_id,
        lot_id,
        warehouse_id,
        location_id,
        reference_id,
        reference_type,
        quantity_change,
        unit_cost,
        created_by
    ) VALUES (
        p_product_id,
        p_lot_id,
        p_warehouse_id,
        p_location_id,
        p_reference_id,
        p_reference_type,
        p_quantity,
        p_unit_cost,
        p_created_by
    );
    
    COMMIT;
    
    SET p_success = TRUE;
    SET p_message = CONCAT('รับสินค้า ', v_product_name, ' จำนวน ', p_quantity, ' หน่วย เข้าล็อต ', p_lot_number, ' สำเร็จ');
END //
DELIMITER ;
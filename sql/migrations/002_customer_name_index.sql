-- Example additive upgrade: speed up customer-name lookups without changing rows.
CREATE INDEX idx_Customer_Name ON Customer (Name);

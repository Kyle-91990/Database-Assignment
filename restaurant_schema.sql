from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from datetime import datetime
import mysql.connector
from typing import List, Optional

app = FastAPI()

# Database configuration
db_config = {
    "host": "localhost",
    "user": "your_username",
    "password": "your_password",
    "database": "restaurant_management"
}

# Pydantic models
class CustomerBase(BaseModel):
    name: str
    phone: str
    email: str

class Customer(CustomerBase):
    customer_id: int
    created_at: datetime

class ReservationCreate(BaseModel):
    customer_id: int
    table_id: int
    datetime: datetime

# API endpoints
@app.post("/customers/", response_model=Customer)
async def create_customer(customer: CustomerBase):
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    
    try:
        query = "INSERT INTO customers (name, phone, email) VALUES (%s, %s, %s)"
        cursor.execute(query, (customer.name, customer.phone, customer.email))
        conn.commit()
        
        # Get the created customer
        cursor.execute("SELECT * FROM customers WHERE customer_id = LAST_INSERT_ID()")
        result = cursor.fetchone()
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        cursor.close()
        conn.close()

@app.get("/available-tables/")
async def get_available_tables(date: str, time: str, party_size: int):
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    
    try:
        query = """
        SELECT t.* FROM tables t
        WHERE t.seats >= %s
        AND t.table_id NOT IN (
            SELECT table_id FROM reservations
            WHERE DATE(datetime) = %s
            AND TIME(datetime) = %s
            AND status = 'booked'
        )
        """
        cursor.execute(query, (party_size, date, time))
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()

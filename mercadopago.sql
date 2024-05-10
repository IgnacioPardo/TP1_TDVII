DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO public;

CREATE TABLE Clave (
    clave_uniforme VARCHAR(50) PRIMARY KEY,
    alias VARCHAR(50) NOT NULL,
    esVirtual BOOLEAN NOT NULL
);

CREATE TABLE Usuarios (
    clave_uniforme VARCHAR(50) PRIMARY KEY,
    CUIT VARCHAR(50),
    email VARCHAR(50),
    nombre VARCHAR(50),
    apellido VARCHAR(50),
    username VARCHAR(50),
    password VARCHAR(50),
    saldo FLOAT,
    fecha_alta DATE,
    FOREIGN KEY (clave_uniforme) REFERENCES Clave(clave_uniforme)
);

CREATE TABLE CuentaBancaria (
    clave_uniforme VARCHAR(50) PRIMARY KEY,
    banco VARCHAR(50),
    FOREIGN KEY (clave_uniforme) REFERENCES Clave(clave_uniforme)
);

CREATE TABLE ProveedorServicio (
    clave_uniforme VARCHAR(50) PRIMARY KEY,
    nombre_empresa VARCHAR(50),
    categoria_servicio VARCHAR(50),
    fecha_alta DATE,
    FOREIGN KEY (clave_uniforme) REFERENCES Clave(clave_uniforme)
);

CREATE TABLE Tarjeta (
    numero VARCHAR(50) PRIMARY KEY,
    vencimiento DATE,
    cvv INTEGER,
    CU VARCHAR(50),
    FOREIGN KEY (CU) REFERENCES Clave(clave_uniforme),
    CHECK (CU IS NOT NULL)
);

-- Add trigger on insert to check if cu is virtual, if not, raise exception

CREATE OR REPLACE FUNCTION check_cu_virtual() 
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT esVirtual FROM Clave WHERE clave_uniforme = NEW.CU) = FALSE THEN
        RAISE EXCEPTION 'CU is not virtual';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_cu_virtual_trigger
BEFORE INSERT ON Tarjeta
FOR EACH ROW
EXECUTE FUNCTION check_cu_virtual();

CREATE TABLE Rendimiento (
    id SERIAL PRIMARY KEY,
    fecha_pago DATE,
    comienzo_plazo DATE NOT NULL,
    fin_plazo DATE,
    TNA FLOAT,
    monto FLOAT
);

CREATE TABLE RendimientoUsuario (
    clave_uniforme VARCHAR(50),
    id INTEGER,
    PRIMARY KEY (clave_uniforme, id),
    FOREIGN KEY (clave_uniforme) REFERENCES Clave(clave_uniforme),
    FOREIGN KEY (id) REFERENCES Rendimiento(id)
);

CREATE TABLE Transaccion (
    codigo SERIAL PRIMARY KEY,
    CU_Origen VARCHAR(50),
    CU_Destino VARCHAR(50),
    monto FLOAT,
    fecha DATE,
    descripcion VARCHAR(50),
    estado VARCHAR(50),
    es_con_tarjeta BOOLEAN,
    numero VARCHAR(50),
    interes FLOAT,
    FOREIGN KEY (CU_Origen) REFERENCES Clave(clave_uniforme),
    FOREIGN KEY (CU_Destino) REFERENCES Clave(clave_uniforme),
    FOREIGN KEY (numero) REFERENCES Tarjeta(numero)
);

CREATE OR REPLACE FUNCTION check_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT saldo FROM Usuarios WHERE clave_uniforme = NEW.CU_Origen) < NEW.monto THEN
        RAISE EXCEPTION 'Not enough balance';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Para el usuario 2:
-- depositar 1000, 
-- comenzar un rendimiento
-- interrumpirlo transfiriendole 500 al usuario 1 (Agregar un trigger para que cuando se cree una transacción, si el usuario tiene un rendimiento activo, se finalice y se cree uno nuevo con el monto restante pero que no se pague)
-- continuar el rendimiento y pagar los rendimientos

CREATE OR REPLACE FUNCTION check_rendimiento()
RETURNS TRIGGER AS $$
BEGIN
    -- Checkear si el usuario tiene un rendimiento activo, es decir sin fecha de fin
    -- Joinear RendimientoUsuario con Rendimiento para obtener el id del rendimiento activo
    IF EXISTS (
        SELECT * FROM RendimientoUsuario JOIN Rendimiento ON RendimientoUsuario.id = Rendimiento.id WHERE clave_uniforme = NEW.CU_Origen AND fin_plazo IS NULL
    ) THEN
        
        -- Finalizar el rendimiento
        UPDATE Rendimiento SET fin_plazo = NEW.fecha WHERE id = (SELECT id FROM RendimientoUsuario WHERE clave_uniforme = NEW.CU_Origen AND fin_plazo IS NULL);
        -- Crear un nuevo rendimiento con el monto restante
        INSERT INTO Rendimiento (fecha_pago, comienzo_plazo, TNA, monto) VALUES (NEW.fecha, NEW.fecha, 0.1, (SELECT saldo FROM Usuarios WHERE clave_uniforme = NEW.CU_Origen) - NEW.monto);
        INSERT INTO RendimientoUsuario (clave_uniforme, id) VALUES (NEW.CU_Origen, (SELECT id FROM Rendimiento WHERE fecha_pago = NEW.fecha AND comienzo_plazo = NEW.fecha AND TNA = 0.1 AND monto = (SELECT saldo FROM Usuarios WHERE clave_uniforme = NEW.CU_Origen) - NEW.monto));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_rendimiento_trigger
BEFORE INSERT ON Transaccion
FOR EACH ROW
WHEN (NEW.es_con_tarjeta = FALSE)
EXECUTE FUNCTION check_rendimiento();

CREATE TRIGGER check_balance_trigger
BEFORE INSERT ON Transaccion
FOR EACH ROW
WHEN (NEW.es_con_tarjeta = FALSE)
EXECUTE FUNCTION check_balance();

CREATE TABLE TransaccionTarjeta (
    codigo INTEGER,
    numero VARCHAR(50),
    PRIMARY KEY (codigo, numero),
    FOREIGN KEY (numero) REFERENCES Tarjeta(numero),
    FOREIGN KEY (codigo) REFERENCES Transaccion(codigo)
);
const express = require('express');
const { randomUUID } = require('crypto');
const { asyncHandler } = require('../errors');
const { authRequired } = require('../services/authService');

const router = express.Router();

const products = new Map();
const parts = new Map();
const shipments = [];
let serviceCaseSeq = 1;

function numberParam(value, fallback = 0) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function productDetail(productUnitId) {
  const id = numberParam(productUnitId, 1);
  if (!products.has(id)) {
    products.set(id, {
      productUnitId: id,
      modelName: 'AVA Product',
      serialNo: `AVA-${String(id).padStart(6, '0')}`,
      qrValue: `PRODUCT-${id}`,
      currentStatus: 'READY',
      progress: {
        productUnitId: id,
        manufacturingStatus: 'READY',
        serviceStatus: 'NONE',
        completedCount: 0,
        totalCount: 0,
        percent: 0
      },
      usedParts: []
    });
  }
  return products.get(id);
}

function partDetail(partId) {
  const id = numberParam(partId, 1);
  if (!parts.has(id)) {
    parts.set(id, {
      partId: id,
      partName: 'AVA Part',
      partNo: `PART-${String(id).padStart(4, '0')}`,
      qrValue: `PART-${id}`,
      quantity: 0,
      safeStock: 0,
      currentStatus: 'READY',
      movements: []
    });
  }
  return parts.get(id);
}

function checklist(productUnitId, mode = 'manufacturing') {
  return {
    productUnitId: numberParam(productUnitId, 1),
    mode,
    status: 'READY',
    items: []
  };
}

function dashboardSummary() {
  return {
    totalProducts: products.size,
    totalParts: parts.size,
    lowStockParts: 0,
    pendingManufacturing: 0,
    pendingService: 0,
    shippedThisMonth: shipments.length
  };
}

function home() {
  return {
    summary: dashboardSummary(),
    recentShipments: shipments.slice(-10).reverse(),
    inventory: Array.from(parts.values())
  };
}

function lookup(qrValue) {
  const value = String(qrValue || '').trim();
  const number = numberParam((value.match(/\d+/) || [1])[0], 1);
  if (/part/i.test(value)) {
    const part = partDetail(number);
    return {
      qrType: 'PART',
      qrValue: value,
      partId: part.partId,
      partName: part.partName,
      currentStatus: part.currentStatus
    };
  }
  if (/product|unit|ava|imei|serial/i.test(value)) {
    const product = productDetail(number);
    return {
      qrType: 'PRODUCT',
      qrValue: value,
      productUnitId: product.productUnitId,
      modelName: product.modelName,
      serialNo: product.serialNo,
      currentStatus: product.currentStatus
    };
  }
  return {
    qrType: 'UNKNOWN',
    qrValue: value
  };
}

router.get('/health', (req, res) => {
  res.json({ status: 'ok', feature: 'AVA_stock', runtime: 'node' });
});

router.use(authRequired);

router.get('/home', (req, res) => {
  res.json(home());
});

router.post('/qr/lookup', (req, res) => {
  res.json(lookup(req.body.qrValue));
});

router.post('/products/receipts', (req, res) => {
  const product = productDetail(req.body.productUnitId || products.size + 1);
  Object.assign(product, req.body, { currentStatus: 'RECEIVED', receivedAt: new Date().toISOString() });
  res.json(product);
});

router.get('/products/by-qr/:qrValue', (req, res) => {
  const found = lookup(req.params.qrValue);
  res.json(found.productUnitId ? productDetail(found.productUnitId) : productDetail(1));
});

router.get('/products/:productUnitId', (req, res) => {
  res.json(productDetail(req.params.productUnitId));
});

router.get('/products/:productUnitId/progress', (req, res) => {
  res.json(productDetail(req.params.productUnitId).progress);
});

router.get('/products/:productUnitId/used-parts', (req, res) => {
  res.json(productDetail(req.params.productUnitId).usedParts);
});

router.get('/products/:productUnitId/manufacturing/checklist', (req, res) => {
  res.json(checklist(req.params.productUnitId, 'manufacturing'));
});

router.post('/products/:productUnitId/manufacturing/save', (req, res) => {
  const product = productDetail(req.params.productUnitId);
  product.lastManufacturingItems = Array.isArray(req.body.items) ? req.body.items : [];
  res.json({ status: 'SAVED', productUnitId: product.productUnitId, items: product.lastManufacturingItems });
});

router.post('/products/:productUnitId/manufacturing/complete', (req, res) => {
  const product = productDetail(req.params.productUnitId);
  product.currentStatus = 'MANUFACTURING_COMPLETE';
  product.lastManufacturingItems = Array.isArray(req.body.items) ? req.body.items : [];
  res.json({ status: 'COMPLETED', productUnitId: product.productUnitId, items: product.lastManufacturingItems });
});

router.post('/products/:productUnitId/service/start', (req, res) => {
  const product = productDetail(req.params.productUnitId);
  const serviceCase = {
    serviceCaseId: serviceCaseSeq++,
    productUnitId: product.productUnitId,
    status: 'OPEN',
    startedAt: new Date().toISOString()
  };
  product.serviceCase = serviceCase;
  res.json(serviceCase);
});

router.get('/service-cases/:serviceCaseId/checklist', (req, res) => {
  res.json({ serviceCaseId: numberParam(req.params.serviceCaseId, 1), mode: 'service', status: 'OPEN', items: [] });
});

router.post('/service-cases/:serviceCaseId/save', (req, res) => {
  res.json({ status: 'SAVED', serviceCaseId: numberParam(req.params.serviceCaseId, 1), items: req.body.items || [] });
});

router.post('/service-cases/:serviceCaseId/complete', (req, res) => {
  res.json({ status: 'COMPLETED', serviceCaseId: numberParam(req.params.serviceCaseId, 1), items: req.body.items || [] });
});

router.get('/parts/inventory', (req, res) => {
  res.json(Array.from(parts.values()));
});

router.get('/parts/by-qr/:qrValue', (req, res) => {
  const found = lookup(req.params.qrValue);
  res.json(found.partId ? partDetail(found.partId) : partDetail(1));
});

router.get('/parts/:partId', (req, res) => {
  res.json(partDetail(req.params.partId));
});

router.post('/parts/:partId/purchase', (req, res) => {
  const part = partDetail(req.params.partId);
  const quantity = numberParam(req.body.quantity, 0);
  part.quantity += quantity;
  part.movements.push({
    id: randomUUID(),
    type: 'PURCHASE',
    quantity,
    memo: req.body.memo || '',
    createdAt: new Date().toISOString()
  });
  res.json(part);
});

router.post('/parts/:partId/adjust', (req, res) => {
  const part = partDetail(req.params.partId);
  const quantity = numberParam(req.body.quantity, 0);
  part.quantity += quantity;
  part.movements.push({
    id: randomUUID(),
    type: 'ADJUST',
    quantity,
    memo: req.body.memo || '',
    createdAt: new Date().toISOString()
  });
  res.json(part);
});

router.get('/parts/:partId/movements', (req, res) => {
  res.json(partDetail(req.params.partId).movements);
});

router.post('/shipments', (req, res) => {
  const shipment = {
    shipmentId: shipments.length + 1,
    destinationName: req.body.destinationName || '',
    imei: req.body.imei || '',
    shippingMethod: req.body.shippingMethod || '',
    shippingDate: req.body.shippingDate || new Date().toISOString().slice(0, 10),
    shipmentStatus: req.body.shipmentStatus || 'DELIVERED',
    productUnitIds: Array.isArray(req.body.productUnitIds) ? req.body.productUnitIds : [],
    createdAt: new Date().toISOString()
  };
  shipments.push(shipment);
  res.json(shipment);
});

router.get('/shipments', (req, res) => {
  res.json(shipments.slice().reverse());
});

router.get('/shipments/:shipmentId', (req, res) => {
  const id = numberParam(req.params.shipmentId, 0);
  res.json(shipments.find((item) => item.shipmentId === id) || { shipmentId: id });
});

router.get('/dashboard/summary', (req, res) => {
  res.json(dashboardSummary());
});

router.get('/dashboard/stock', (req, res) => {
  res.json(Array.from(parts.values()));
});

router.get('/dashboard/recent-shipments', (req, res) => {
  res.json(shipments.slice(-20).reverse());
});

router.get('/dashboard/part-usage', (req, res) => {
  res.json([]);
});

router.get('/dashboard/shipment-history', (req, res) => {
  res.json(shipments.slice().reverse());
});

router.get('/admin/:resource?', (req, res) => {
  res.json([]);
});

router.post('/admin/:resource?', (req, res) => {
  res.json({ status: 'SAVED', ...req.body });
});

router.put('/admin/:resource/:id?', (req, res) => {
  res.json({ status: 'UPDATED', id: req.params.id || '', ...req.body });
});

router.delete('/admin/:resource/:id?', (req, res) => {
  res.json({ status: 'DELETED', id: req.params.id || '' });
});

module.exports = router;

package uk.bit1.mcpserver.refund;

import java.time.Instant;

public record CustomerOrder(
    String id,
    String customerId,
    Instant placedAt,
    Instant deliveredAt,
    String status,
    long totalMinor,
    String currency,
    Instant refundedAt) {}

# AI Booking Assistance - Salesforce Car Rental

## Overview
The AI Booking Assistance module uses Salesforce Agentforce invocable Apex actions to help customers search available rental vehicles, create booking holds, retrieve booking details and access payment or verification links.

## Main Components

### 1. AgentSearchVehicles
- Accepts pickup and return date-time.
- Supports city, category, seating, transmission, fuel and price filters.
- Uses VehicleSearchService as the availability source.
- Returns up to five matching vehicles with pricing details.
- Does not invent vehicle availability.

### 2. AgentCreateBooking
- Creates a Pending Payment booking hold.
- Resolves customer identity through CustomerContext.
- Validates the selected vehicle.
- Uses BookingService to create the hold.
- Provides payment and KYC verification links.
- Does not mark a booking confirmed before payment.

### 3. AgentGetBooking
- Retrieves booking details using the booking number.
- Uses BookingRepository to retrieve customer-owned bookings.
- Returns booking status, vehicle, dates and payment status.
- Prevents access to another customer's booking.

### 4. AgentSupport
- Formats currency in INR.
- Formats date and time in IST.
- Creates readable booking summaries for agent responses.

## Booking Assistance Flow

1. Customer provides rental dates and location.
2. Agent invokes AgentSearchVehicles.
3. Customer selects a vehicle from the returned results.
4. Agent invokes AgentCreateBooking after customer confirmation.
5. System creates a Pending Payment hold.
6. Customer receives the required payment or KYC verification link.
7. Booking confirmation depends on successful payment.

## Security and Reliability
- Customer identity is resolved through CustomerContext.
- Booking ownership is enforced during retrieval.
- Vehicle availability is checked through VehicleSearchService.
- Invalid inputs return user-readable error messages.
- Booking creation does not bypass payment confirmation.

## Test Coverage
AgentActionsTest includes scenarios for:
- Vehicle search and booking hold creation.
- KYC verification link for unverified customers.
- Preventing access to another customer's booking.
- Explicit cancellation confirmation.
- Booking and payment link states.
- Invalid inputs and rental date validation.

## Related Apex Components
- AgentSearchVehicles
- AgentCreateBooking
- AgentGetBooking
- AgentGetPaymentLink
- AgentCancelBooking
- AgentSupport
- AgentActionsTest
- CustomerContext
- BookingService
- VehicleSearchService
- BookingRepository

## Project Responsibility Mapping
This module supports the AI Booking Assistance responsibility by connecting conversational agent actions to the existing Salesforce vehicle search and booking services.

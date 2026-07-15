"use client";

import {
  CarFront,
  LoaderCircle,
  ShieldCheck,
  X,
} from "lucide-react";
import { useState, type FormEvent } from "react";
import type {
  CreateVehicleInput,
  VehicleSummary,
  VehicleType,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type AddCustomerVehicleModalProps = {
  customer: CustomerSummary;
  onClose: () => void;
  onCreated: (vehicle: VehicleSummary) => void;
};

const vehicleTypes: Array<{
  value: VehicleType;
  label: string;
}> = [
  { value: "CAR", label: "Car" },
  { value: "MOTORCYCLE", label: "Motorcycle" },
  { value: "BUS", label: "Bus" },
  { value: "TRUCK", label: "Truck" },
  { value: "CNG", label: "CNG" },
  { value: "PICKUP", label: "Pickup" },
  { value: "MICROBUS", label: "Microbus" },
  { value: "AMBULANCE", label: "Ambulance" },
  {
    value: "CONSTRUCTION_EQUIPMENT",
    label: "Construction equipment",
  },
  { value: "OTHER", label: "Other" },
];

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function optional(value: string) {
  const normalized = value.trim();
  return normalized || undefined;
}

export function AddCustomerVehicleModal({
  customer,
  onClose,
  onCreated,
}: AddCustomerVehicleModalProps) {
  const [vehicleType, setVehicleType] = useState<VehicleType>("CAR");
  const [registrationNumber, setRegistrationNumber] = useState("");
  const [manufacturer, setManufacturer] = useState("");
  const [modelName, setModelName] = useState("");
  const [manufacturingYear, setManufacturingYear] = useState("");
  const [color, setColor] = useState("");
  const [chassisNumber, setChassisNumber] = useState("");
  const [engineNumber, setEngineNumber] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    const year = manufacturingYear ? Number(manufacturingYear) : undefined;

    if (
      year !== undefined &&
      (!Number.isInteger(year) || year < 1886 || year > 2100)
    ) {
      setError("Manufacturing year must be between 1886 and 2100.");
      return;
    }

    if (
      !registrationNumber.trim() &&
      !chassisNumber.trim() &&
      !engineNumber.trim()
    ) {
      setError(
        "Enter at least a registration number, chassis number, or engine number.",
      );
      return;
    }

    const input: CreateVehicleInput = {
      customerId: customer.id,
      vehicleType,
      registrationNumber: optional(registrationNumber),
      manufacturer: optional(manufacturer),
      modelName: optional(modelName),
      manufacturingYear: year,
      color: optional(color),
      chassisNumber: optional(chassisNumber),
      engineNumber: optional(engineNumber),
    };

    setSubmitting(true);

    try {
      const response = await fetch("/api/management/vehicles", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(input),
      });

      const result = (await response.json()) as
        | VehicleSummary
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Vehicle registration failed.",
        );
        return;
      }

      onCreated(result as VehicleSummary);
    } catch {
      setError("The web panel could not reach the Vehicle service.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2600] grid place-items-center bg-[#17345f]/48 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !submitting) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-customer-vehicle-title"
        className="flex max-h-[94vh] w-full max-w-[780px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.28)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <CarFront className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                Customer Asset
              </span>
            </div>
            <h2
              id="add-customer-vehicle-title"
              className="mt-2 text-[18px] font-semibold text-[#344b72]"
            >
              Add Vehicle
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              {customerName(customer)} Â· {customer.customerCode}
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="grid h-9 w-9 place-items-center rounded-full text-[#71819c] hover:bg-[#f2f6fb]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto px-6 py-5"
        >
          <div className="grid gap-4 md:grid-cols-2">
            <label className="text-[11px] font-semibold text-[#52698e]">
              Vehicle type
              <select
                value={vehicleType}
                onChange={(event) =>
                  setVehicleType(event.target.value as VehicleType)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
              >
                {vehicleTypes.map((item) => (
                  <option key={item.value} value={item.value}>
                    {item.label}
                  </option>
                ))}
              </select>
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Registration number
              <input
                value={registrationNumber}
                onChange={(event) =>
                  setRegistrationNumber(event.target.value)
                }
                maxLength={100}
                placeholder="DHAKA-METRO-GA-12-3456"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Manufacturer
              <input
                value={manufacturer}
                onChange={(event) => setManufacturer(event.target.value)}
                maxLength={120}
                placeholder="Toyota"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Model
              <input
                value={modelName}
                onChange={(event) => setModelName(event.target.value)}
                maxLength={120}
                placeholder="Axio"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Manufacturing year
              <input
                type="number"
                min={1886}
                max={2100}
                value={manufacturingYear}
                onChange={(event) =>
                  setManufacturingYear(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Color
              <input
                value={color}
                onChange={(event) => setColor(event.target.value)}
                maxLength={60}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Chassis number
              <input
                value={chassisNumber}
                onChange={(event) =>
                  setChassisNumber(event.target.value)
                }
                maxLength={120}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Engine number
              <input
                value={engineNumber}
                onChange={(event) => setEngineNumber(event.target.value)}
                maxLength={120}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>
          </div>

          <div className="mt-5 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <div className="flex items-center gap-2 font-semibold text-[#344b72]">
              <ShieldCheck className="h-4 w-4 text-[#357cf4]" />
              Identity validation
            </div>
            <p className="mt-1">
              Solid Tracker checks registration, chassis, and engine identity
              against existing vehicle records before creation.
            </p>
          </div>

          {error ? (
            <p className="mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </p>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#e2e8f1] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[4px] border border-[#cfd8e7] px-5 text-[11px] font-semibold text-[#52698e]"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <CarFront className="h-4 w-4" />
              )}
              Register Vehicle
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}
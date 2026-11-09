// Must be imported before anything else so auto-instrumentation can patch http, fastify, undici, etc.
import "./config";
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { OTLPMetricExporter } from "@opentelemetry/exporter-metrics-otlp-http";
import { OTLPLogExporter } from "@opentelemetry/exporter-logs-otlp-http";
import { BatchLogRecordProcessor } from "@opentelemetry/sdk-logs";
import { PeriodicExportingMetricReader } from "@opentelemetry/sdk-metrics";
import { trace, metrics, diag, DiagConsoleLogger, DiagLogLevel, SpanStatusCode, type Span, type Attributes } from "@opentelemetry/api";

/**
 * Exports traces + metrics over OTLP/HTTP.
 * Either set the standard OTEL_EXPORTER_OTLP_ENDPOINT / OTEL_EXPORTER_OTLP_HEADERS,
 * or the shortcuts DASH0_ENDPOINT (e.g. https://ingress.<region>.dash0.com) + DASH0_AUTH_TOKEN (+ DASH0_DATASET).
 */
function exporterOptions(signal: "traces" | "metrics" | "logs") {
  const dash0 = process.env.DASH0_ENDPOINT;
  if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT || !dash0) return {}; // standard env vars are read by the exporter itself
  const headers: Record<string, string> = {};
  if (process.env.DASH0_AUTH_TOKEN) headers.Authorization = `Bearer ${process.env.DASH0_AUTH_TOKEN}`;
  if (process.env.DASH0_DATASET) headers["Dash0-Dataset"] = process.env.DASH0_DATASET;
  return { url: `${dash0.replace(/\/$/, "")}/v1/${signal}`, headers };
}

const enabled = Boolean(process.env.OTEL_EXPORTER_OTLP_ENDPOINT || process.env.DASH0_ENDPOINT);

if (enabled) {
  // Print export failures (bad token, wrong endpoint) instead of failing silently.
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.WARN);
  const sdk = new NodeSDK({
    serviceName: process.env.OTEL_SERVICE_NAME ?? "orbit-backend",
    traceExporter: new OTLPTraceExporter(exporterOptions("traces")),
    metricReaders: [
      new PeriodicExportingMetricReader({
        exporter: new OTLPMetricExporter(exporterOptions("metrics")),
        exportIntervalMillis: 15000,
      }),
    ],
    // Fastify's pino logs are bridged into OpenTelemetry logs (with trace ids) and sent to Dash0.
    logRecordProcessors: [new BatchLogRecordProcessor({ exporter: new OTLPLogExporter(exporterOptions("logs")) })],
    instrumentations: [
      getNodeAutoInstrumentations({
        "@opentelemetry/instrumentation-fs": { enabled: false },
        "@opentelemetry/instrumentation-dns": { enabled: false },
        "@opentelemetry/instrumentation-net": { enabled: false },
      }),
    ],
  });
  sdk.start();
  const shutdown = () => sdk.shutdown().finally(() => process.exit(0));
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
}

export const otelEnabled = enabled;
const tracer = trace.getTracer("orbit-backend");
const meter = metrics.getMeter("orbit-backend");

export const matchCounter = meter.createCounter("orbit.matches.created", { description: "Mutual matches created" });
export const swipeCounter = meter.createCounter("orbit.swipes", { description: "Swipes by target type and direction" });
export const llmDuration = meter.createHistogram("orbit.llm.duration", { unit: "ms", description: "OpenAI call latency" });

/** Run fn inside a span named `name`; records errors and duration. */
export async function traced<T>(name: string, attrs: Attributes, fn: (span: Span) => Promise<T>): Promise<T> {
  return tracer.startActiveSpan(name, { attributes: attrs }, async (span) => {
    try {
      const out = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return out;
    } catch (err) {
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR, message: (err as Error).message });
      throw err;
    } finally {
      span.end();
    }
  });
}

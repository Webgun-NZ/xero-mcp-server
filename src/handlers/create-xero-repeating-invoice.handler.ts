import { xeroClient } from "../clients/xero-client.js";
import { XeroClientResponse } from "../types/tool-response.js";
import { formatError } from "../helpers/format-error.js";
import { RepeatingInvoice } from "xero-node";
import { getClientHeaders } from "../helpers/get-client-headers.js";
import {
  buildRepeatingInvoice,
  RepeatingInvoiceInput,
} from "../helpers/build-repeating-invoice.js";

async function createRepeatingInvoice(
  input: RepeatingInvoiceInput,
): Promise<RepeatingInvoice | undefined> {
  const repeatingInvoice = buildRepeatingInvoice(input);

  await xeroClient.authenticate();

  const response = await xeroClient.accountingApi.createRepeatingInvoices(
    xeroClient.tenantId,
    {
      repeatingInvoices: [repeatingInvoice],
    }, // repeatingInvoices
    true, //summarizeErrors
    undefined, //idempotencyKey
    getClientHeaders(),
  );
  return response.body.repeatingInvoices?.[0];
}

/**
 * Create a new repeating invoice template in Xero
 */
export async function createXeroRepeatingInvoice(
  input: RepeatingInvoiceInput,
): Promise<XeroClientResponse<RepeatingInvoice>> {
  try {
    const createdRepeatingInvoice = await createRepeatingInvoice(input);

    if (!createdRepeatingInvoice) {
      throw new Error("Repeating invoice creation failed.");
    }

    return {
      result: createdRepeatingInvoice,
      isError: false,
      error: null,
    };
  } catch (error) {
    return {
      result: null,
      isError: true,
      error: formatError(error),
    };
  }
}

import { createIntentRouter } from "@/lib/intent/http-boundary";
import { createSupabaseIntentService } from "@/lib/intent/service";

export const dynamic = "force-dynamic";

const handler = createIntentRouter({ createService: createSupabaseIntentService });

export const POST = handler;
export const GET = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
export const HEAD = handler;

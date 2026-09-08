<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Used as `role:ADMIN,ENGINEER` on a route, always after
        // `auth:sanctum` so there is a user to check.
        $middleware->alias([
            'role' => \App\Http\Middleware\EnsureRole::class,
        ]);

        /*
         * This application has no browser login page — it is an API with
         * a React client — so a guest is never redirected anywhere.
         *
         * The default Authenticate middleware calls route('login') for
         * any request that does not explicitly ask for JSON, and with no
         * such route defined that threw RouteNotFoundException, turning
         * every unauthenticated call into a 500 that hid the real 401.
         * Returning null keeps it an AuthenticationException, which the
         * handler below renders as a 401.
         */
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        /*
         * Anything under /api answers with JSON, whatever the client's
         * Accept header says.
         *
         * Without this an unauthenticated API call was redirected to a
         * route named `login`, which this project does not have, so the
         * caller got a 500 with an HTML error page masking what was
         * really a 401. Axios happens to send an Accept header that
         * avoided it; curl and the browser's own fetch do not, and an API
         * should not behave differently depending on that.
         */
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson()
        );

        /*
         * And the 401 itself. The line above settles the format; this
         * settles the status, because the default path for an
         * unauthenticated user is a redirect to a route named `login`
         * that an API-only application does not have.
         */
        $exceptions->render(function (\Illuminate\Auth\AuthenticationException $e, Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json(['message' => 'Sign in to continue.'], 401);
            }

            return null;
        });
    })->create();

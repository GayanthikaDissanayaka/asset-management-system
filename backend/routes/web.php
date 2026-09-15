<?php

use Illuminate\Support\Facades\Route;

/*
 * Serving the React app.
 *
 * The build is copied into public/, so Apache serves index.html, the
 * hashed JS and CSS under /static, and the images directly as files.
 * That covers "/" and every real asset.
 *
 * It does NOT cover the app's own routes. /dashboard, /assets,
 * /hv-length and /login exist only inside React Router -- there is no
 * such file on disk, so Laravel's .htaccess hands them to index.php,
 * and without the catch-all below Laravel answers 404. The symptom is
 * the one everybody hits: the app works when you click through it, and
 * breaks the moment you refresh the page or paste a link to it.
 *
 * So any GET that is not an API call and not a real file returns the
 * same index.html, and React Router reads the path from there.
 */

/** The built SPA shell, or a plain explanation if it has not been built. */
$spa = function () {
    $index = public_path('index.html');

    if (! file_exists($index)) {
        return response(
            "The React build is not in public/ yet.\n\n"
            . "Run:  php artisan app:deploy-frontend\n"
            . "(or:  cd frontend && npm run build   then copy build/ into backend/public/)\n",
            503
        )->header('Content-Type', 'text/plain');
    }

    /*
     * No-store on the shell only. The hashed files under /static are
     * immutable and cached hard by the browser; index.html is the one
     * file that must never be cached, or a deploy leaves people running
     * yesterday's app pointing at today's asset names.
     */
    return response(file_get_contents($index))
        ->header('Content-Type', 'text/html; charset=UTF-8')
        ->header('Cache-Control', 'no-store, must-revalidate');
};

Route::get('/', $spa);

/*
 * Everything else that is not /api. The API is registered separately in
 * routes/api.php and must keep returning JSON 404s rather than HTML --
 * an API call answered with a page of markup is far harder to diagnose
 * than a 404.
 */
Route::get('/{any}', $spa)
    ->where('any', '^(?!api|sanctum|storage).*$');

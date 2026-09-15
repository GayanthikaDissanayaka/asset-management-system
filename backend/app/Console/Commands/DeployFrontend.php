<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Symfony\Component\Finder\Finder;

/**
 * Copies the built React app into Laravel's public/ directory.
 *
 * WHY A COMMAND AND NOT `copy build\* public\`.
 *
 * public/ is not an empty folder waiting for the frontend. It already
 * holds Laravel's own front controller and rewrite rules:
 *
 *   index.php    the entry point for every API request
 *   .htaccess    the rewrite that makes routing work at all
 *
 * A copy that overwrote or removed either takes the whole backend down,
 * and "I copied the build folder in and now nothing works" is a hard
 * failure to diagnose because the API stops answering entirely. This
 * command refuses to touch them.
 *
 * It also clears the previous build's hashed assets first. Without that,
 * public/static accumulates every JS bundle ever deployed -- harmless
 * to serve, but it grows without limit and makes it impossible to tell
 * which files are live.
 *
 *   php artisan app:deploy-frontend
 *   php artisan app:deploy-frontend --build    (runs npm run build first)
 */
class DeployFrontend extends Command
{
    protected $signature = 'app:deploy-frontend
                            {--build : Run "npm run build" in frontend/ first}
                            {--source= : Path to the build output (default ../frontend/build)}';

    protected $description = 'Copy the built React app into public/ so Apache serves it';

    /**
     * Laravel's own files. Never deleted, never overwritten by the copy.
     * favicon.ico is listed because the React build ships one too, and
     * the app's icon should win -- so it is overwritable but not
     * deletable.
     */
    private const PROTECTED_FILES = ['index.php', '.htaccess'];

    public function handle(): int
    {
        $source = $this->option('source')
            ?: realpath(base_path('../frontend/build'))
            ?: base_path('../frontend/build');

        if ($this->option('build')) {
            $frontend = realpath(base_path('../frontend'));

            if (! $frontend) {
                $this->error('Cannot find the frontend directory beside the backend.');

                return self::FAILURE;
            }

            $this->info('Building the React app. This takes a few minutes...');

            // Inherit stdout so the build's own progress is visible
            // rather than the command appearing to hang.
            $exit = 0;
            passthru('cd /d ' . escapeshellarg($frontend) . ' && npm run build', $exit);

            if ($exit !== 0) {
                $this->error('npm run build failed. Nothing was copied.');

                return self::FAILURE;
            }
        }

        if (! is_dir($source) || ! file_exists($source . DIRECTORY_SEPARATOR . 'index.html')) {
            $this->error("No React build found at: {$source}");
            $this->line('Run it with --build, or build the frontend first.');

            return self::FAILURE;
        }

        $public = public_path();

        // Old hashed bundles, so public/static does not accumulate every
        // build ever made.
        $this->clearDirectory($public . DIRECTORY_SEPARATOR . 'static');

        $copied = 0;
        $finder = (new Finder())->files()->in($source)->ignoreDotFiles(false);

        foreach ($finder as $file) {
            $relative = $file->getRelativePathname();

            if (in_array(basename($relative), self::PROTECTED_FILES, true)) {
                $this->warn("  skipped {$relative} — that is Laravel's own file");
                continue;
            }

            $target = $public . DIRECTORY_SEPARATOR . $relative;
            $dir    = dirname($target);

            if (! is_dir($dir)) {
                mkdir($dir, 0755, true);
            }

            copy($file->getRealPath(), $target);
            $copied++;
        }

        $this->newLine();
        $this->info("Copied {$copied} files into public/.");

        foreach (self::PROTECTED_FILES as $keep) {
            $state = file_exists($public . DIRECTORY_SEPARATOR . $keep) ? 'present' : 'MISSING';
            $this->line("  {$keep}: {$state}");
        }

        if (! file_exists($public . DIRECTORY_SEPARATOR . 'index.php')) {
            $this->error('public/index.php is gone — the API will not respond. Restore it from git.');

            return self::FAILURE;
        }

        $this->newLine();
        $this->line('The app is now served by Apache from public/.');
        $this->line('Deep links like /assets work through the catch-all in routes/web.php.');

        return self::SUCCESS;
    }

    /** Empties a directory without removing the directory itself. */
    private function clearDirectory(string $path): void
    {
        if (! is_dir($path)) {
            return;
        }

        foreach ((new Finder())->in($path)->depth('< 20')->files() as $file) {
            @unlink($file->getRealPath());
        }

        // Directories, deepest first, so a parent is only removed once
        // its children are gone.
        $dirs = iterator_to_array((new Finder())->in($path)->directories());
        usort($dirs, fn ($a, $b) => strlen($b->getRealPath()) <=> strlen($a->getRealPath()));

        foreach ($dirs as $dir) {
            @rmdir($dir->getRealPath());
        }
    }
}

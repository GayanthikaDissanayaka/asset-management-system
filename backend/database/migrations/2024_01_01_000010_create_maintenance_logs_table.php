<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('maintenance_logs', function (Blueprint $table) {
            $table->bigIncrements('log_id');
            $table->unsignedBigInteger('asset_id')->nullable();
            $table->unsignedBigInteger('segment_id')->nullable();
            $table->enum('action_type', ['installed', 'inspected', 'repaired', 'replaced', 'decommissioned']);
            $table->unsignedInteger('performed_by');
            $table->dateTime('performed_at')->useCurrent();
            $table->text('remarks')->nullable();
            $table->string('photo_path', 255)->nullable();

            $table->foreign('asset_id')->references('asset_id')->on('assets')->onDelete('cascade');
            $table->foreign('segment_id')->references('segment_id')->on('line_segments')->onDelete('cascade');
            $table->foreign('performed_by')->references('user_id')->on('users');
            $table->index('asset_id');
            $table->index('segment_id');
            $table->index('performed_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('maintenance_logs');
    }
};

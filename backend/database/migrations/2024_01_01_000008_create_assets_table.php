<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('assets', function (Blueprint $table) {
            $table->bigIncrements('asset_id');
            $table->string('segment_no', 30);
            $table->unsignedInteger('asset_type_id');
            $table->unsignedInteger('depot_id');
            $table->unsignedInteger('feeder_id')->nullable();
            $table->decimal('quantity', 10, 3)->default(1);
            $table->decimal('capacity_kva', 10, 2)->nullable();
            $table->string('material', 50)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->enum('status', ['active', 'faulty', 'under_repair', 'decommissioned'])->default('active');
            $table->date('installed_date')->nullable();
            $table->unsignedInteger('installed_by')->nullable();
            $table->unsignedInteger('last_verified_by')->nullable();
            $table->dateTime('last_verified_at')->nullable();
            $table->text('remarks')->nullable();
            $table->timestamps();

            $table->foreign('asset_type_id')->references('type_id')->on('asset_types');
            $table->foreign('depot_id')->references('depot_id')->on('depots')->onDelete('cascade');
            $table->foreign('feeder_id')->references('feeder_id')->on('feeders')->onDelete('set null');
            $table->foreign('installed_by')->references('user_id')->on('users')->onDelete('set null');
            $table->foreign('last_verified_by')->references('user_id')->on('users')->onDelete('set null');
            $table->unique(['depot_id', 'segment_no']);
            $table->index(['asset_type_id']);
            $table->index(['depot_id']);
            $table->index(['feeder_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('assets');
    }
};

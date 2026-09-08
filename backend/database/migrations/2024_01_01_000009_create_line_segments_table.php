<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('line_segments', function (Blueprint $table) {
            $table->bigIncrements('segment_id');
            $table->string('segment_code', 30);
            $table->unsignedInteger('feeder_id');
            $table->unsignedInteger('asset_type_id');
            $table->enum('voltage_level', ['LV', 'MV', 'HV']);
            $table->string('from_point', 150)->nullable();
            $table->string('to_point', 150)->nullable();
            $table->decimal('length_km', 8, 3);
            $table->enum('status', ['active', 'faulty', 'proposed', 'decommissioned'])->default('active');
            $table->timestamps();

            $table->foreign('feeder_id')->references('feeder_id')->on('feeders')->onDelete('cascade');
            $table->foreign('asset_type_id')->references('type_id')->on('asset_types');
            $table->unique(['feeder_id', 'segment_code']);
            $table->index('voltage_level');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('line_segments');
    }
};

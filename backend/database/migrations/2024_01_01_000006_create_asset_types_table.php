<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('asset_types', function (Blueprint $table) {
            $table->increments('type_id');
            $table->unsignedInteger('category_id');
            $table->string('type_name', 100);
            $table->enum('unit_of_measure', ['nos', 'km', 'm', 'kVA'])->default('nos');
            $table->boolean('is_line_asset')->default(false);
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('category_id')->references('category_id')->on('asset_categories')->onDelete('cascade');
            $table->unique(['category_id', 'type_name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('asset_types');
    }
};
